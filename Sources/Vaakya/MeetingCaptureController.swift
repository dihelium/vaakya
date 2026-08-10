import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
@Observable
final class MeetingCaptureController {
    enum Phase: Equatable {
        case idle
        case requestingPermissions
        case starting
        case recording
        case stopping
        case failed
    }

    enum PermissionIssue: Equatable {
        case microphone
        case screenRecording
    }

    private let coordinator: Coordinator
    private let runner: AudioTranscriptionJobRunner
    private var capture: MeetingAudioCapture?
    private var microphoneReserved = false
    private var totalPaused: TimeInterval = 0
    private var pauseBeganAt: Date?

    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    private(set) var isPaused = false
    private(set) var microphoneLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var lastError: String?
    private(set) var permissionIssue: PermissionIssue?
    private(set) var completedJobID: String?
    private(set) var recoveryDirectory: URL?

    init(coordinator: Coordinator, runner: AudioTranscriptionJobRunner) {
        self.coordinator = coordinator
        self.runner = runner
    }

    var isRecording: Bool { phase == .recording && !isPaused }
    var isSessionActive: Bool { phase == .recording }

    var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Wall-clock elapsed minus time spent paused.
    func elapsedSeconds(at date: Date = Date()) -> Int {
        guard let startedAt else { return 0 }
        var paused = totalPaused
        if let pauseBeganAt {
            paused += date.timeIntervalSince(pauseBeganAt)
        }
        return max(0, Int(date.timeIntervalSince(startedAt) - paused))
    }

    func start() async {
        guard phase == .idle || phase == .failed else { return }
        clearOutcome()

        guard coordinator.reserveMicrophoneForMeeting() else {
            fail("Finish the current dictation first, then start recording.")
            return
        }
        microphoneReserved = true
        phase = .requestingPermissions

        guard await requestMicrophoneIfNeeded() else {
            permissionIssue = .microphone
            fail("Vaakya needs Microphone access to hear you. Allow it in Privacy & Security, then try again.")
            releaseMicrophone()
            return
        }

        guard requestScreenRecordingIfNeeded() else {
            permissionIssue = .screenRecording
            fail("Allow Screen & System Audio Recording for Vaakya, then quit and reopen Vaakya if macOS asks. Recording never falls back to mic-only.")
            releaseMicrophone()
            return
        }

        phase = .starting
        let directory = Paths.transcriptionJobsDirectory
            .appendingPathComponent("meeting-capture-\(UUID().uuidString)", isDirectory: true)
        recoveryDirectory = directory

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let newCapture = try MeetingAudioCapture(
                stagingDirectory: directory,
                levelUpdate: { [weak self] source, level in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase == .recording, !self.isPaused else { return }
                        switch source {
                        case .microphone: self.microphoneLevel = level
                        case .system: self.systemLevel = level
                        }
                    }
                },
                failure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        await self?.captureFailed(message)
                    }
                }
            )
            capture = newCapture
            try await newCapture.start()
            startedAt = Date()
            isPaused = false
            totalPaused = 0
            pauseBeganAt = nil
            phase = .recording
        } catch {
            capture?.abort()
            capture = nil
            fail("Recording could not start: \(error.localizedDescription)")
            releaseMicrophone()
        }
    }

    func pause() {
        guard phase == .recording, !isPaused, let capture else { return }
        isPaused = true
        pauseBeganAt = Date()
        microphoneLevel = 0
        systemLevel = 0
        capture.setPaused(true)
    }

    func resume() {
        guard phase == .recording, isPaused, let capture else { return }
        if let pauseBeganAt {
            totalPaused += Date().timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        isPaused = false
        capture.setPaused(false)
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    @discardableResult
    func stop() async -> String? {
        guard phase == .recording, let capture else { return nil }
        if isPaused { resume() }
        phase = .stopping
        isPaused = false
        microphoneLevel = 0
        systemLevel = 0

        do {
            let result = try await capture.stop()
            self.capture = nil
            guard result.hasAudibleAudio else {
                throw MeetingAudioCapture.CaptureError.emptyRecording
            }

            let sourceName = Self.sourceName(for: startedAt ?? Date())
            let jobID = try await runner.enqueueCapturedAudio(url: result.mixedURL, sourceName: sourceName)
            try? FileManager.default.removeItem(at: result.stagingDirectory)
            recoveryDirectory = nil
            completedJobID = jobID
            phase = .idle
            startedAt = nil
            totalPaused = 0
            pauseBeganAt = nil
            releaseMicrophone()
            return jobID
        } catch {
            self.capture = nil
            // Salvage: if mix left a usable meeting.wav, try enqueueing it once more.
            if let recovery = recoveryDirectory {
                let salvage = recovery.appendingPathComponent("meeting.wav")
                if FileManager.default.fileExists(atPath: salvage.path) {
                    do {
                        let sourceName = Self.sourceName(for: startedAt ?? Date())
                        let jobID = try await runner.enqueueCapturedAudio(url: salvage, sourceName: sourceName)
                        try? FileManager.default.removeItem(at: recovery)
                        recoveryDirectory = nil
                        completedJobID = jobID
                        phase = .idle
                        startedAt = nil
                        totalPaused = 0
                        pauseBeganAt = nil
                        releaseMicrophone()
                        return jobID
                    } catch {
                        // fall through to failure with both errors
                    }
                }
            }
            let recovery = recoveryDirectory?.path
            let suffix = recovery.map { " Captured files remain at \($0)." } ?? ""
            fail("Recording could not be saved: \(error.localizedDescription).\(suffix)")
            releaseMicrophone()
            return nil
        }
    }

    /// Retry enqueueing a left-behind meeting.wav after a failed stop.
    func saveRecoveredCapture() async {
        guard phase == .failed, let recovery = recoveryDirectory else { return }
        let salvage = recovery.appendingPathComponent("meeting.wav")
        guard FileManager.default.fileExists(atPath: salvage.path) else {
            fail("No recovered meeting.wav found at \(recovery.path).")
            return
        }
        do {
            let sourceName = Self.sourceName(for: Date())
            let jobID = try await runner.enqueueCapturedAudio(url: salvage, sourceName: sourceName)
            try? FileManager.default.removeItem(at: recovery)
            recoveryDirectory = nil
            completedJobID = jobID
            phase = .idle
            lastError = nil
            releaseMicrophone()
        } catch {
            fail("Could not save recovered capture: \(error.localizedDescription)")
        }
    }

    func reset() {
        guard phase == .failed || phase == .idle else { return }
        clearOutcome()
        phase = .idle
        releaseMicrophone()
    }

    func openPermissionSettings() {
        let anchor: String
        switch permissionIssue {
        case .microphone:
            anchor = "Privacy_Microphone"
        case .screenRecording:
            anchor = "Privacy_ScreenCapture"
        case nil:
            anchor = "Privacy"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    func abortForTermination() {
        capture?.abort()
        capture = nil
        releaseMicrophone()
    }

    static func sourceName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Meeting \(formatter.string(from: date))"
    }

    private func requestMicrophoneIfNeeded() async -> Bool {
        switch MicRecorder.micStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                MicRecorder.requestMicPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestScreenRecordingIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let granted = CGRequestScreenCaptureAccess()
        return granted || CGPreflightScreenCaptureAccess()
    }

    private func captureFailed(_ message: String) async {
        guard phase == .recording else { return }
        lastError = "Capture stopped early: \(message)"
        _ = await stop()
    }

    private func fail(_ message: String) {
        lastError = message
        phase = .failed
        startedAt = nil
        isPaused = false
        totalPaused = 0
        pauseBeganAt = nil
        microphoneLevel = 0
        systemLevel = 0
    }

    private func clearOutcome() {
        lastError = nil
        permissionIssue = nil
        completedJobID = nil
        recoveryDirectory = nil
        isPaused = false
        totalPaused = 0
        pauseBeganAt = nil
        microphoneLevel = 0
        systemLevel = 0
    }

    private func releaseMicrophone() {
        guard microphoneReserved else { return }
        microphoneReserved = false
        coordinator.releaseMicrophoneFromMeeting()
    }
}

final class MeetingAudioCapture: NSObject, @unchecked Sendable {
    enum Source: Sendable {
        case microphone
        case system
    }

    struct Result: Sendable {
        let mixedURL: URL
        let stagingDirectory: URL
        let hasAudibleAudio: Bool
    }

    enum CaptureError: LocalizedError {
        case noMicrophone
        case noDisplay
        case invalidSystemAudio
        case emptyRecording
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "No microphone input is available"
            case .noDisplay: return "No active display is available for system audio capture"
            case .invalidSystemAudio: return "ScreenCaptureKit returned an unsupported audio buffer"
            case .emptyRecording: return "No audible microphone or system audio was captured"
            case .writer(let message): return message
            }
        }
    }

    private static let sampleRate = 16_000.0
    private let targetFormat: AVAudioFormat
    private let writeSettings: [String: Any]
    private let stagingDirectory: URL
    private let micURL: URL
    private let systemURL: URL
    private let mixedURL: URL
    private let micWriter: TimelineAudioWriter
    private let systemWriter: TimelineAudioWriter
    private let levelUpdate: @Sendable (Source, Float) -> Void
    private let failure: @Sendable (String) -> Void
    private let engine = AVAudioEngine()
    private var stream: SCStream?
    private var streamDelegate: MeetingStreamDelegate?
    private var systemOutput: MeetingSystemAudioOutput?
    private var videoOutput: MeetingNoopVideoOutput?
    private var configurationObserver: NSObjectProtocol?
    private let stateLock = NSLock()
    private var stopped = false
    private var paused = false
    private var lastMicLevelUpdate = 0.0
    private var lastSystemLevelUpdate = 0.0

    init(stagingDirectory: URL,
         levelUpdate: @escaping @Sendable (Source, Float) -> Void,
         failure: @escaping @Sendable (String) -> Void) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Self.sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw CaptureError.writer("Vaakya could not create the meeting audio format")
        }
        targetFormat = format
        writeSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        self.stagingDirectory = stagingDirectory
        micURL = stagingDirectory.appendingPathComponent("mic.wav")
        systemURL = stagingDirectory.appendingPathComponent("system.wav")
        mixedURL = stagingDirectory.appendingPathComponent("meeting.wav")
        self.levelUpdate = levelUpdate
        self.failure = failure
        micWriter = TimelineAudioWriter(url: micURL, format: format, settings: writeSettings)
        systemWriter = TimelineAudioWriter(url: systemURL, format: format, settings: writeSettings)
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 4

        let delegate = MeetingStreamDelegate(owner: self)
        let audioOutput = MeetingSystemAudioOutput(owner: self)
        let noopOutput = MeetingNoopVideoOutput()
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
        try newStream.addStreamOutput(audioOutput,
                                      type: .audio,
                                      sampleHandlerQueue: DispatchQueue(label: "vaakya.meeting.system-audio"))
        try newStream.addStreamOutput(noopOutput,
                                      type: .screen,
                                      sampleHandlerQueue: DispatchQueue(label: "vaakya.meeting.screen-noop"))

        streamDelegate = delegate
        systemOutput = audioOutput
        videoOutput = noopOutput
        stream = newStream

        let timelineStart = ProcessInfo.processInfo.systemUptime
        micWriter.startTimeline(at: timelineStart)
        systemWriter.startTimeline(at: timelineStart)

        do {
            try await newStream.startCapture()
            try startMicrophone()
            observeMicrophoneConfiguration()
        } catch {
            try? await newStream.stopCapture()
            stream = nil
            throw error
        }
    }

    func stop() async throws -> Result {
        guard markStopped() else { throw CaptureError.emptyRecording }
        removeConfigurationObserver()
        if let stream {
            try? await stream.stopCapture()
        }
        self.stream = nil
        stopMicrophone()

        let micSnapshot = micWriter.close()
        let systemSnapshot = systemWriter.close()
        if let error = micSnapshot.error ?? systemSnapshot.error {
            throw CaptureError.writer(error)
        }
        let audible = max(micSnapshot.peak, systemSnapshot.peak) >= 0.001
        guard micSnapshot.contentFrames > 0 || systemSnapshot.contentFrames > 0 else {
            throw CaptureError.emptyRecording
        }

        try Self.mix(
            microphone: micSnapshot.contentFrames > 0 ? micURL : nil,
            system: systemSnapshot.contentFrames > 0 ? systemURL : nil,
            output: mixedURL,
            format: targetFormat,
            settings: writeSettings
        )
        return Result(mixedURL: mixedURL, stagingDirectory: stagingDirectory, hasAudibleAudio: audible)
    }

    func abort() {
        guard markStopped() else { return }
        removeConfigurationObserver()
        stopMicrophone()
        micWriter.close()
        systemWriter.close()
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        self.stream = nil
    }

    /// Drop frames while paused (timer freezes, no silence written).
    func setPaused(_ value: Bool) {
        stateLock.lock()
        paused = value
        stateLock.unlock()
    }

    fileprivate func consumeSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopped, !isPaused,
              CMSampleBufferIsValid(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            return
        }

        var descriptionCopy = streamDescription
        guard let inputFormat = AVAudioFormat(streamDescription: &descriptionCopy) else {
            failure(CaptureError.invalidSystemAudio.localizedDescription)
            return
        }
        guard let inputBuffer = Self.pcmBuffer(from: sampleBuffer, format: inputFormat) else {
            failure(CaptureError.invalidSystemAudio.localizedDescription)
            return
        }
        guard let systemOutput else { return }
        if systemOutput.converter == nil ||
            systemOutput.converter?.inputFormat.sampleRate != inputFormat.sampleRate ||
            systemOutput.converter?.inputFormat.channelCount != inputFormat.channelCount {
            systemOutput.converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        guard let converter = systemOutput.converter,
              let converted = convert(inputBuffer, using: converter) else { return }
        let duration = Double(converted.frameLength) / Self.sampleRate
        let callbackStart = ProcessInfo.processInfo.systemUptime - duration
        systemWriter.append(converted, firstBufferStart: callbackStart)
        publishLevel(for: .system, buffer: converted)
    }

    fileprivate func streamStopped(with error: Error) {
        guard !isStopped else { return }
        failure("System audio stopped: \(error.localizedDescription)")
    }

    private func startMicrophone() throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.noMicrophone
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.writer("Vaakya could not convert microphone audio")
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !self.isStopped, !self.isPaused else { return }
            guard let converted = self.convert(buffer, using: converter) else { return }
            let duration = Double(converted.frameLength) / Self.sampleRate
            let callbackStart = ProcessInfo.processInfo.systemUptime - duration
            self.micWriter.append(converted, firstBufferStart: callbackStart)
            self.publishLevel(for: .microphone, buffer: converted)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func stopMicrophone() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func observeMicrophoneConfiguration() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.isStopped else { return }
            self.failure("The microphone device changed during capture")
        }
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }

    private func convert(_ input: AVAudioPCMBuffer,
                         using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = Self.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var conversionError: NSError?
        let provider = AudioConverterInputProvider(input)
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            provider.next(status: inputStatus)
        }
        if status == .error {
            failure("Audio conversion failed: \(conversionError?.localizedDescription ?? "unknown error")")
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    private func publishLevel(for source: Source, buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var peak: Float = 0
        for index in 0..<count { peak = max(peak, abs(channel[index])) }

        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let shouldPublish: Bool
        switch source {
        case .microphone:
            shouldPublish = now - lastMicLevelUpdate >= 0.08
            if shouldPublish { lastMicLevelUpdate = now }
        case .system:
            shouldPublish = now - lastSystemLevelUpdate >= 0.08
            if shouldPublish { lastSystemLevelUpdate = now }
        }
        stateLock.unlock()
        if shouldPublish { levelUpdate(source, peak) }
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    private var isPaused: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return paused
    }

    private func markStopped() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stopped else { return false }
        stopped = true
        paused = false
        return true
    }

    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer,
                                  format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames

        var blockBuffer: CMBlockBuffer?
        let bufferCount = max(1, Int(format.channelCount))
        let listSize = MemoryLayout<AudioBufferList>.size
            + max(0, bufferCount - 1) * MemoryLayout<AudioBuffer>.size
        let sourceList = AudioBufferList.allocate(maximumBuffers: bufferCount)
        defer { free(sourceList.unsafeMutablePointer) }

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceList.unsafeMutablePointer,
            bufferListSize: listSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let destinationList = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        for index in 0..<min(destinationList.count, sourceList.count) {
            guard let source = sourceList[index].mData,
                  let destination = destinationList[index].mData else { continue }
            let byteCount = Int(min(sourceList[index].mDataByteSize,
                                    destinationList[index].mDataByteSize))
            memcpy(destination, source, byteCount)
        }
        return pcm
    }

    private static func mix(microphone micURL: URL?,
                            system systemURL: URL?,
                            output outputURL: URL,
                            format: AVAudioFormat,
                            settings: [String: Any]) throws {
        let micFile = try micURL.map { try AVAudioFile(forReading: $0) }
        let systemFile = try systemURL.map { try AVAudioFile(forReading: $0) }
        guard micFile != nil || systemFile != nil else { throw CaptureError.emptyRecording }

        // AVAudioFile(forWriting:) fails if the path already exists.
        try? FileManager.default.removeItem(at: outputURL)
        let output = try AVAudioFile(forWriting: outputURL, settings: settings,
                                     commonFormat: format.commonFormat,
                                     interleaved: format.isInterleaved)
        let capacity: AVAudioFrameCount = 8192
        let hasTwoSources = micFile != nil && systemFile != nil

        while true {
            let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            let systemBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)!
            // AVAudioFile.read throws GenericObjCError at EOF instead of
            // returning zero frames. Guard framePosition and swallow EOF.
            _ = safeRead(micFile, into: micBuffer, frameCount: capacity)
            _ = safeRead(systemFile, into: systemBuffer, frameCount: capacity)
            let frames = max(micBuffer.frameLength, systemBuffer.frameLength)
            if frames == 0 { break }

            let mixed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            mixed.frameLength = frames
            let mic = micBuffer.floatChannelData?[0]
            let system = systemBuffer.floatChannelData?[0]
            let destination = mixed.floatChannelData![0]
            let gain: Float = hasTwoSources ? 0.78 : 1
            for index in 0..<Int(frames) {
                let micSample = index < Int(micBuffer.frameLength) ? mic?[index] ?? 0 : 0
                let systemSample = index < Int(systemBuffer.frameLength) ? system?[index] ?? 0 : 0
                destination[index] = max(-1, min(1, (micSample + systemSample) * gain))
            }
            try output.write(from: mixed)
        }
    }

    /// Read frames without treating end-of-file as a hard failure.
    @discardableResult
    private static func safeRead(_ file: AVAudioFile?,
                                 into buffer: AVAudioPCMBuffer,
                                 frameCount: AVAudioFrameCount) -> AVAudioFrameCount {
        guard let file else {
            buffer.frameLength = 0
            return 0
        }
        if file.framePosition >= file.length {
            buffer.frameLength = 0
            return 0
        }
        do {
            try file.read(into: buffer, frameCount: frameCount)
            return buffer.frameLength
        } catch {
            buffer.frameLength = 0
            return 0
        }
    }
}

private final class AudioConverterInputProvider: @unchecked Sendable {
    private let input: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false

    init(_ input: AVAudioPCMBuffer) {
        self.input = input
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if supplied {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return input
    }
}

private final class TimelineAudioWriter: @unchecked Sendable {
    struct Snapshot: Sendable {
        let contentFrames: AVAudioFramePosition
        let peak: Float
        let error: String?
    }

    private let url: URL
    private let format: AVAudioFormat
    private let settings: [String: Any]
    private let queue: DispatchQueue
    private var timelineStart = 0.0
    private var file: AVAudioFile?
    private var firstBufferWritten = false
    private var contentFrames: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var error: String?

    init(url: URL, format: AVAudioFormat, settings: [String: Any]) {
        self.url = url
        self.format = format
        self.settings = settings
        queue = DispatchQueue(label: "vaakya.meeting.writer.\(url.deletingPathExtension().lastPathComponent)")
    }

    func startTimeline(at uptime: Double) {
        queue.sync { timelineStart = uptime }
    }

    func append(_ buffer: AVAudioPCMBuffer, firstBufferStart: Double) {
        queue.sync {
            guard error == nil else { return }
            do {
                if file == nil {
                    try? FileManager.default.removeItem(at: url)
                    file = try AVAudioFile(forWriting: url, settings: settings,
                                           commonFormat: format.commonFormat,
                                           interleaved: format.isInterleaved)
                }
                if !firstBufferWritten {
                    let leadingSeconds = max(0, firstBufferStart - timelineStart)
                    try writeSilence(frames: AVAudioFramePosition(leadingSeconds * format.sampleRate))
                    firstBufferWritten = true
                }
                try file?.write(from: buffer)
                contentFrames += AVAudioFramePosition(buffer.frameLength)
                if let channel = buffer.floatChannelData?[0] {
                    for index in 0..<Int(buffer.frameLength) {
                        peak = max(peak, abs(channel[index]))
                    }
                }
            } catch {
                self.error = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func close() -> Snapshot {
        queue.sync {
            file = nil
            return Snapshot(contentFrames: contentFrames, peak: peak, error: error)
        }
    }

    private func writeSilence(frames: AVAudioFramePosition) throws {
        var remaining = frames
        let chunkFrames: AVAudioFrameCount = 8192
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(chunkFrames)))
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            if let channel = buffer.floatChannelData?[0] {
                channel.initialize(repeating: 0, count: Int(count))
            }
            try file?.write(from: buffer)
            remaining -= AVAudioFramePosition(count)
        }
    }
}

private final class MeetingStreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    weak var owner: MeetingAudioCapture?

    init(owner: MeetingAudioCapture) {
        self.owner = owner
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        owner?.streamStopped(with: error)
    }
}

private final class MeetingSystemAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    weak var owner: MeetingAudioCapture?
    var converter: AVAudioConverter?

    init(owner: MeetingAudioCapture) {
        self.owner = owner
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        owner?.consumeSystemAudio(sampleBuffer)
    }
}

private final class MeetingNoopVideoOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {}
}
