import AVFoundation
import Foundation
import VaakyaCore

/// Records from the default input device via AVAudioEngine and produces
/// 16 kHz mono Float32 samples (plan 1.3). Latched recording has no duration
/// cap. Its optional watchdog fires only after sustained empty audio.
final class MicRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noInput
        case alreadyRecording
        case notRecording
        var errorDescription: String? {
            switch self {
            case .noInput: return "No audio input device available."
            case .alreadyRecording: return "Already recording."
            case .notRecording: return "Not recording."
            }
        }
    }

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private let emptyAudioTimeoutSeconds: TimeInterval
    private let watchdogQueue = DispatchQueue(label: "vaakya.mic.empty-audio-watchdog")
    private var emptyAudioWatchdog: EmptyAudioWatchdog?
    private var emptyAudioTimer: DispatchSourceTimer?
    private var emptyAudioTimeoutHandler: (@Sendable () -> Void)?
    private var recording = false

    init(emptyAudioTimeoutSeconds: TimeInterval = 90) {
        self.emptyAudioTimeoutSeconds = emptyAudioTimeoutSeconds
    }

    /// Microphone permission state (modern API, macOS 14+).
    enum MicPermission: Equatable {
        case undetermined, denied, granted
    }

    static var micStatus: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    static var hasMicPermission: Bool { micStatus == .granted }

    /// Modern TCC request API. Hardened-runtime builds must also carry the
    /// audio-input entitlement for macOS to present the prompt.
    static func requestMicPermission(_ completion: @escaping @Sendable (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            completion(granted)
        }
    }

    /// Read/write the recording flag under `lock` — it is also read on the
    /// engine's render thread (review fix: no unsynchronized flag access).
    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recording
    }

    /// Starts recording. Supplying an empty-audio handler enables the inactivity
    /// fallback used by latch mode. A nil handler leaves recording release-driven.
    func start(onEmptyAudioTimeout: (@Sendable () -> Void)? = nil) throws {
        lock.lock()
        let already = recording
        lock.unlock()
        guard !already else { throw RecorderError.alreadyRecording }
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInput
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Convert to 16 kHz mono Float32 (pure, tested in VaakyaCore).
            let raw = self.float32Samples(from: buffer)
            let converted = PCMConverter.convertTo16kMonoFloat32(
                samples: raw,
                inputRate: inputFormat.sampleRate,
                inputChannels: Int(inputFormat.channelCount))
            // Append under the lock, re-checking the flag: a callback that started
            // before stop() must not append after stop() returned the samples
            // (review fix — no check-then-act, no tail drop).
            let now = ProcessInfo.processInfo.systemUptime
            self.lock.lock()
            if self.recording {
                self.samples.append(contentsOf: converted)
                if var watchdog = self.emptyAudioWatchdog {
                    watchdog.observe(samples: converted, at: now)
                    self.emptyAudioWatchdog = watchdog
                }
            }
            self.lock.unlock()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        // Set the flag only after the engine is actually running (review fix:
        // if start() throws, the recorder must not wedge as 'already recording').
        lock.lock()
        recording = true
        if onEmptyAudioTimeout != nil, emptyAudioTimeoutSeconds > 0 {
            emptyAudioWatchdog = EmptyAudioWatchdog(
                timeoutSeconds: emptyAudioTimeoutSeconds,
                startedAt: ProcessInfo.processInfo.systemUptime)
            emptyAudioTimeoutHandler = onEmptyAudioTimeout
        }
        lock.unlock()
        startEmptyAudioTimerIfNeeded()
    }

    func stop() -> [Float] {
        lock.lock()
        let wasRecording = recording
        recording = false
        let timer = emptyAudioTimer
        emptyAudioTimer = nil
        emptyAudioWatchdog = nil
        emptyAudioTimeoutHandler = nil
        lock.unlock()
        timer?.cancel()
        guard wasRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func startEmptyAudioTimerIfNeeded() {
        lock.lock()
        let shouldStart = recording && emptyAudioWatchdog != nil
        lock.unlock()
        guard shouldStart else { return }

        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        let checkInterval = min(1.0, max(0.05, emptyAudioTimeoutSeconds / 10))
        timer.schedule(deadline: .now() + emptyAudioTimeoutSeconds,
                       repeating: checkInterval,
                       leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.checkEmptyAudioTimeout()
        }

        lock.lock()
        guard recording, emptyAudioWatchdog != nil else {
            lock.unlock()
            timer.resume()
            timer.cancel()
            return
        }
        emptyAudioTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func checkEmptyAudioTimeout() {
        lock.lock()
        guard recording,
              let watchdog = emptyAudioWatchdog,
              watchdog.hasTimedOut(at: ProcessInfo.processInfo.systemUptime) else {
            lock.unlock()
            return
        }
        // Clear before invoking so the periodic timer can deliver at most once.
        let timer = emptyAudioTimer
        let handler = emptyAudioTimeoutHandler
        emptyAudioTimer = nil
        emptyAudioTimeoutHandler = nil
        emptyAudioWatchdog = nil
        lock.unlock()
        timer?.cancel()
        handler?()
    }

    private func float32Samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var out = [Float]()
        out.reserveCapacity(frames * channels)
        if buffer.format.isInterleaved {
            out.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frames * channels))
        } else {
            for f in 0..<frames {
                for c in 0..<channels {
                    out.append(channelData[c][f])
                }
            }
        }
        return out
    }
}
