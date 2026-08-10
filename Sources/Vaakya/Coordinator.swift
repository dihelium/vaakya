import AppKit
import AVFoundation
import Foundation
import VaakyaCore

/// Central state for UI observation (recording indicator, suggestion badge).
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    var phase: Phase = .idle
    var modelsReady = false
    var pendingSuggestionCount = 0
    var lastError: String?
}

/// Thread-safe flag box so Sendable closures can read a mutable setting.
final class Stage2Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var flag: Bool

    init(enabled: Bool) {
        flag = enabled
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        flag = newValue
    }
}

/// Orchestrates the full loop (plan §1 / §3):
/// hotkey → MicRecorder → VAD trim → FluidAudio ASR → PersonalizationPipeline
/// → TextInjector → EditWatcher. Also owns onboarding-triggered prep.
@MainActor
final class Coordinator {
    private enum RecordingMode {
        case hold
        case latched
    }

    let state = AppState()
    let db: VaakyaDatabase
    private let pipeline: PersonalizationPipeline
    private let hotkey: HotkeyMonitor
    private let recorder: MicRecorder
    private let transcriber: any Transcriber
    private let injector: TextInjector
    private var cleanupModel: (any CleanupModel)?
    private var activeRecordingMode: RecordingMode?
    private var meetingCaptureOwnsMicrophone = false
    /// Live stage-2 toggle (Settings); the pipeline reads this on every dictation.
    /// A Sendable box so the pipeline's @Sendable closure can read it.
    let stage2Gate = Stage2Gate(enabled: true)

    /// True when the event tap was actually created (Input Monitoring granted).
    var hotkeyActive: Bool { hotkey.isActive }

    /// Comma-joined list of missing permissions — shown in the menu bar so
    /// "hold-to-talk does nothing" is actionable (user feedback 2026-08-02).
    var permissionSummary: String {
        var missing: [String] = []
        if MicRecorder.micStatus != .granted { missing.append("Microphone") }
        if !TextInjector.hasAccessibilityPermission() { missing.append("Accessibility") }
        if !HotkeyMonitor.preflight() { missing.append("Input Monitoring") }
        return missing.isEmpty ? "" : "Missing: " + missing.joined(separator: ", ")
    }

    /// Detailed mic state for the menu (helps debug the "not in Settings" case).
    var micStatusText: String {
        switch MicRecorder.micStatus {
        case .granted: return "Microphone: granted"
        case .denied: return "Microphone: denied — enable in System Settings"
        case .undetermined: return "Microphone: not asked yet — hold Option to ask"
        }
    }

    init(config: AppConfig, db: VaakyaDatabase, transcriber: any Transcriber,
         cleanupModel: (any CleanupModel)? = nil) {
        self.db = db
        self.transcriber = transcriber
        self.cleanupModel = cleanupModel
        stage2Gate.set(config.stage2Enabled)
        pipeline = PersonalizationPipeline(db: db) { [weak stage2Gate] in
            stage2Gate?.value ?? false
        }
        recorder = MicRecorder(emptyAudioTimeoutSeconds: config.emptyAudioTimeoutSeconds)
        injector = TextInjector(method: TextInjector.InjectionMethod(rawValue: config.injectionMethod) ?? .auto)
        hotkey = HotkeyMonitor(keyCode: config.hotkeyKeyCode, doubleTapEnabled: config.doubleTapEnabled)
    }

    // MARK: - lifecycle

    func start() {
        hotkey.onGesture = { [weak self] gesture in
            Task { @MainActor [weak self] in
                self?.handle(gesture: gesture)
            }
        }
        hotkey.start()
        if !hotkey.isActive {
            state.lastError = "Hotkey inactive — Input Monitoring permission missing. Open Onboarding to grant it."
        }
        refreshBadge()
    }

    func stop() {
        hotkey.stop()
    }

    /// Prepares the ASR models after persisted consent has been verified by the
    /// caller. FluidAudio reuses its on-disk cache on subsequent launches.
    func prepareModels() async {
        do {
            try await transcriber.prepare()
            state.modelsReady = true
        } catch {
            state.lastError = "Model load failed: \(error.localizedDescription)"
        }
    }

    // MARK: - gesture handling

    private func handle(gesture: HotkeyMonitor.Gesture) {
        switch gesture {
        case .holdBegan:
            beginRecording(mode: .hold)
        case .doubleTapBegan:
            beginRecording(mode: .latched)
        case .holdEnded, .latchEnded:
            // If a mic-permission prompt is up, the release must cancel the
            // pending recording start (review fix: no ambient capture without
            // a held key).
            micPromptStillHeld = false
            endRecording()
        case .singleTap:
            // Latch mode off / ignored in v1 unless double-tap latch is on.
            break
        }
    }

    /// Re-check permissions and recover without a relaunch (user feedback 2026-08-02):
    /// - Input Monitoring granted since launch → re-arm the event tap.
    /// - Microphone is NOT requested here (that would spam the TCC prompt on
    ///   every menu open, review finding); it is only requested on an explicit
    ///   user action (hold to dictate, or Onboarding's Grant button).
    func refreshPermissions() {
        if !hotkeyActive && HotkeyMonitor.preflight() {
            hotkey.stop()
            hotkey.start()
            if hotkeyActive {
                state.lastError = nil
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            state.lastError = "Microphone permission denied — enable it in System Settings."
        default:
            break
        }
        refreshBadge()
    }

    private func beginRecording(mode: RecordingMode) {
        guard !meetingCaptureOwnsMicrophone else {
            state.lastError = "Meeting notes is using the microphone. Stop the meeting before dictating."
            return
        }
        guard state.phase == .idle else { return }
        guard state.modelsReady else {
            state.lastError = "Speech models are not ready yet — complete onboarding or wait for startup loading."
            return
        }
        // Explicit, actionable permission checks — silent failure is the bug
        // the user hit (hold-to-talk did nothing with no explanation).
        guard HotkeyMonitor.preflight() else {
            state.lastError = "Input Monitoring permission missing — open Onboarding and grant it."
            return
        }
        switch MicRecorder.micStatus {
        case .granted:
            break
        case .undetermined:
            requestMicAndRecord(mode: mode)
            return
        case .denied:
            state.lastError = "Microphone permission denied — enable it in System Settings."
            return
        }
        beginRecordingAfterPermissions(mode: mode)
    }

    /// Fires the TCC prompt once per session (review fix: serialized, and the
    /// grant continuation re-validates that the user is still holding).
    private var micRequestInFlight = false
    private var micPromptStillHeld = false

    private func requestMicAndRecord(mode: RecordingMode) {
        guard !micRequestInFlight else { return }
        micRequestInFlight = true
        micPromptStillHeld = true
        state.lastError = "Microphone permission requested — grant it in the prompt, then hold Option again."
        MicRecorder.requestMicPermission { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.micRequestInFlight = false
                let wasStillHeld = self.micPromptStillHeld
                self.micPromptStillHeld = false
                if granted {
                    if wasStillHeld {
                        self.beginRecordingAfterPermissions(mode: mode)
                    } else {
                        self.state.lastError = "Microphone granted — hold Option again to record."
                    }
                } else {
                    self.state.lastError = "Microphone permission denied — enable it in System Settings."
                }
            }
        }
    }

    private func beginRecordingAfterPermissions(mode: RecordingMode) {
        guard state.phase == .idle else { return }
        guard TextInjector.hasAccessibilityPermission() else {
            state.lastError = "Accessibility permission missing — needed to type at your cursor."
            return
        }
        state.lastError = nil
        do {
            let timeoutHandler: (@Sendable () -> Void)?
            if mode == .latched {
                timeoutHandler = { [weak self] in
                    _ = Task { @MainActor [weak self] in
                        self?.emptyAudioTimedOut()
                    }
                }
            } else {
                timeoutHandler = nil
            }
            try recorder.start(onEmptyAudioTimeout: timeoutHandler)
            activeRecordingMode = mode
            state.phase = .recording
            FloatingIndicator.shared.show(state: state)
        } catch {
            state.lastError = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func endRecording() {
        guard state.phase == .recording else { return }
        activeRecordingMode = nil
        let samples = recorder.stop()
        state.phase = .transcribing
        FloatingIndicator.shared.show(state: state)
        Task {
            await transcribeAndInject(samples)
        }
    }

    private func emptyAudioTimedOut() {
        guard state.phase == .recording, activeRecordingMode == .latched else { return }
        hotkey.cancelLatch()
        endRecording()
    }

    private func transcribeAndInject(_ samples: [Float]) async {
        defer {
            state.phase = .idle
            FloatingIndicator.shared.hide()
            refreshBadge()
        }
        guard !samples.isEmpty else { return }
        do {
            let trimmed = await transcriber.trimSilence(samples)
            guard !trimmed.isEmpty else { return }
            let rawText = try await transcriber.transcribe(trimmed)
            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            let appContext = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let result = try await pipeline.process(rawText: rawText,
                                                    cleanupModel: cleanupModel,
                                                    appContext: appContext)

            // Install the AX observer before posting asynchronous CGEvents so
            // it sees the injection land and can arm on the completed text.
            // Use the pipeline's returned id rather than a latest-row lookup.
            EditWatcherManager.shared.startWatcher(db: db,
                                                   injectedText: result.text,
                                                   dictationId: result.dictationId,
                                                   appContext: appContext)
            injector.inject(result.text)
        } catch {
            state.lastError = "Dictation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - helpers

    /// Serializes the shared microphone between long meeting capture and the
    /// short hotkey path. Main-actor isolation makes the reservation atomic
    /// with respect to hotkey gesture handling.
    func reserveMicrophoneForMeeting() -> Bool {
        guard !meetingCaptureOwnsMicrophone,
              !micRequestInFlight,
              state.phase == .idle else { return false }
        hotkey.cancelLatch()
        meetingCaptureOwnsMicrophone = true
        state.lastError = nil
        return true
    }

    func releaseMicrophoneFromMeeting() {
        meetingCaptureOwnsMicrophone = false
    }

    func refreshBadge() {
        state.pendingSuggestionCount = (try? db.pendingSuggestionCount()) ?? 0
    }
}
