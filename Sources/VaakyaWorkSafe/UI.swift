import AppKit
import AVFoundation
import Observation
import SwiftUI

struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Text("Vaakya Work Safe")
            .foregroundStyle(.secondary)
            .onAppear { environment.coordinator.refreshPermissions() }

        switch environment.coordinator.state.phase {
        case .idle: Text("Hold Left Option to dictate")
        case .recording: Label("Recording…", systemImage: "record.circle").foregroundStyle(.red)
        case .transcribing: Label("Transcribing locally…", systemImage: "waveform")
        }

        if let error = environment.coordinator.state.lastError {
            Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
        }

        Divider()
        Button("Show Vaakya") { WindowManager.shared.openMain() }
        Button("Permissions and model…") { WindowManager.shared.openOnboarding() }
        Button("Re-check permissions") { environment.coordinator.refreshPermissions() }
        Divider()
        Button("Quit Vaakya") { NSApp.terminate(nil) }
    }
}

struct WorkSafeView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Vaakya")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("Work-safe local dictation")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            statusCard

            VStack(alignment: .leading, spacing: 12) {
                Label("Hold Left Option, speak, then release", systemImage: "option")
                Label("Audio is held in memory only", systemImage: "memorychip")
                Label("Transcript text is not saved", systemImage: "externaldrive.badge.xmark")
                Label("No meetings, imported audio, AI runners, telemetry, or clipboard access", systemImage: "lock.shield")
            }
            .font(.body)

            HStack {
                Button("Permissions and model…") {
                    WindowManager.shared.openOnboarding()
                }
                .buttonStyle(.borderedProminent)
                Button("Re-check") {
                    environment.coordinator.refreshPermissions()
                }
            }
            Spacer()
        }
        .padding(36)
        .frame(minWidth: 620, minHeight: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: ready ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(ready ? "Ready to dictate" : "Setup required")
                    .font(.headline)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var ready: Bool {
        environment.coordinator.state.modelsReady
            && environment.coordinator.hotkeyActive
            && MicRecorder.micStatus == .granted
            && TextInjector.hasAccessibilityPermission()
    }

    private var statusText: String {
        if !environment.coordinator.state.modelsReady { return "The local speech model is not ready." }
        return environment.coordinator.permissionSummary
    }
}

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var micGranted = MicRecorder.micStatus == .granted
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var inputGranted = CGPreflightListenEventAccess()
    @State private var preparingModel = false

    private var ready: Bool {
        micGranted && accessibilityGranted && inputGranted
            && environment.coordinator.state.modelsReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Set up Vaakya Work Safe")
                    .font(.title2.weight(.semibold))
                Text("Three macOS permissions and one local speech-model download are required.")
                    .foregroundStyle(.secondary)
            }

            permissionRow(
                title: "Microphone",
                detail: "Used only while Left Option is held.",
                granted: micGranted,
                action: requestMicrophone
            )
            permissionRow(
                title: "Accessibility",
                detail: "Used only to type the transcript at your cursor.",
                granted: accessibilityGranted,
                action: requestAccessibility
            )
            permissionRow(
                title: "Input Monitoring",
                detail: "Observes Left Option modifier changes only.",
                granted: inputGranted,
                action: requestInputMonitoring
            )

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local speech model").font(.headline)
                    Text("One-time ~450 MB download via FluidAudio; transcription is local afterward.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if environment.coordinator.state.modelsReady {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else if preparingModel {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Download") {
                        Task {
                            preparingModel = true
                            await environment.prepareModelsWithConsent()
                            preparingModel = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            if let error = environment.coordinator.state.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Re-check permissions") { refresh() }
                Spacer()
                Button("Open Vaakya") {
                    WindowManager.shared.closeOnboarding()
                    WindowManager.shared.openMain()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
            }
        }
        .padding(30)
        .frame(minWidth: 600, minHeight: 580)
        .onAppear { refresh() }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func requestMicrophone() {
        MicRecorder.requestMicPermission { granted in
            Task { @MainActor in micGranted = granted }
        }
    }

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
    }

    private func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
    }

    private func refresh() {
        micGranted = MicRecorder.micStatus == .granted
        accessibilityGranted = AXIsProcessTrusted()
        inputGranted = CGPreflightListenEventAccess()
        environment.coordinator.refreshPermissions()
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private init() {}

    func openMain() {
        guard let environment = AppEnvironment.startup.environment else { return }
        if mainWindow == nil {
            let view = WorkSafeView().environment(environment)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Vaakya Work Safe"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 650, height: 460))
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboarding() {
        guard let environment = AppEnvironment.startup.environment else { return }
        if onboardingWindow == nil {
            let view = OnboardingView().environment(environment)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Vaakya Work Safe — Setup"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 600))
            window.center()
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeOnboarding() {
        onboardingWindow?.close()
    }
}

@MainActor
final class FloatingIndicator {
    static let shared = FloatingIndicator()
    private var window: NSWindow?

    private init() {}

    func show(state: AppState) {
        let view = FloatingIndicatorView(state: state)
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: view))
            created.styleMask = [.borderless, .nonactivatingPanel]
            created.level = .floating
            created.isOpaque = false
            created.backgroundColor = .clear
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = created
        } else if let host = window?.contentViewController as? NSHostingController<FloatingIndicatorView> {
            host.rootView = view
        }
        positionNearCursor()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionNearCursor() {
        guard let window,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let size = NSSize(width: 180, height: 46)
        window.setContentSize(size)
        let visible = screen.visibleFrame
        let mouse = NSEvent.mouseLocation
        let x = min(max(mouse.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(mouse.y + 24, visible.minY + 8), visible.maxY - size.height - 8)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct FloatingIndicatorView: View {
    let state: AppState

    var body: some View {
        Label(
            state.phase == .recording ? "Recording" : "Transcribing locally",
            systemImage: state.phase == .recording ? "record.circle.fill" : "waveform"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(state.phase == .recording ? .red : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
    }
}
