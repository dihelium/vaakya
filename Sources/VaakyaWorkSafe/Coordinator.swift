import AppKit
import AVFoundation
import Foundation
import Observation

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
    var lastError: String?
}

/// In-memory, local-only loop: Left Option → microphone → local ASR → Unicode.
@MainActor
final class Coordinator {
    let state = AppState()
    private let hotkey = HotkeyMonitor()
    private let recorder = MicRecorder()
    private let transcriber: any Transcriber
    private let injector = TextInjector()
    private var micRequestInFlight = false
    private var micPromptStillHeld = false

    init(transcriber: any Transcriber) {
        self.transcriber = transcriber
    }

    var hotkeyActive: Bool { hotkey.isActive }

    var permissionSummary: String {
        var missing: [String] = []
        if MicRecorder.micStatus != .granted { missing.append("Microphone") }
        if !TextInjector.hasAccessibilityPermission() { missing.append("Accessibility") }
        if !HotkeyMonitor.preflight() { missing.append("Input Monitoring") }
        return missing.isEmpty ? "All required permissions granted" : "Missing: " + missing.joined(separator: ", ")
    }

    func start() {
        hotkey.onGesture = { [weak self] gesture in
            Task { @MainActor [weak self] in
                switch gesture {
                case .began: self?.beginRecording()
                case .ended:
                    self?.micPromptStillHeld = false
                    self?.endRecording()
                }
            }
        }
        hotkey.start()
        if !hotkey.isActive {
            state.lastError = "Input Monitoring is required for the Left Option hotkey."
        }
    }

    func stop() {
        hotkey.stop()
        if state.phase == .recording {
            _ = recorder.stop()
        }
        state.phase = .idle
        FloatingIndicator.shared.hide()
    }

    func prepareModels() async {
        do {
            try await transcriber.prepare()
            state.modelsReady = true
            state.lastError = nil
        } catch {
            state.lastError = "Speech model preparation failed: \(error.localizedDescription)"
        }
    }

    func refreshPermissions() {
        if !hotkeyActive, HotkeyMonitor.preflight() {
            hotkey.stop()
            hotkey.start()
        }
        if MicRecorder.micStatus == .denied {
            state.lastError = "Microphone access is denied in System Settings."
        } else if hotkeyActive, TextInjector.hasAccessibilityPermission() {
            state.lastError = nil
        }
    }

    private func beginRecording() {
        guard state.phase == .idle else { return }
        guard state.modelsReady else {
            state.lastError = "Download the local speech model before dictating."
            return
        }
        guard HotkeyMonitor.preflight() else {
            state.lastError = "Input Monitoring permission is missing."
            return
        }
        guard TextInjector.hasAccessibilityPermission() else {
            state.lastError = "Accessibility permission is needed to type at the cursor."
            return
        }

        switch MicRecorder.micStatus {
        case .granted:
            beginRecordingAfterPermissions()
        case .undetermined:
            requestMicAndRecord()
        case .denied:
            state.lastError = "Microphone access is denied in System Settings."
        }
    }

    private func requestMicAndRecord() {
        guard !micRequestInFlight else { return }
        micRequestInFlight = true
        micPromptStillHeld = true
        MicRecorder.requestMicPermission { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.micRequestInFlight = false
                let stillHeld = self.micPromptStillHeld
                self.micPromptStillHeld = false
                if granted, stillHeld {
                    self.beginRecordingAfterPermissions()
                } else if granted {
                    self.state.lastError = "Microphone granted. Hold Left Option again to dictate."
                } else {
                    self.state.lastError = "Microphone access was not granted."
                }
            }
        }
    }

    private func beginRecordingAfterPermissions() {
        guard state.phase == .idle else { return }
        do {
            try recorder.start()
            state.phase = .recording
            state.lastError = nil
            FloatingIndicator.shared.show(state: state)
        } catch {
            state.lastError = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func endRecording() {
        guard state.phase == .recording else { return }
        let samples = recorder.stop()
        state.phase = .transcribing
        FloatingIndicator.shared.show(state: state)
        Task { await transcribeAndInject(samples) }
    }

    private func transcribeAndInject(_ samples: [Float]) async {
        defer {
            state.phase = .idle
            FloatingIndicator.shared.hide()
        }
        guard !samples.isEmpty else { return }
        do {
            let trimmed = await transcriber.trimSilence(samples)
            guard !trimmed.isEmpty else { return }
            let text = try await transcriber.transcribe(trimmed)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            injector.inject(text)
        } catch {
            state.lastError = "Dictation failed: \(error.localizedDescription)"
        }
    }
}
