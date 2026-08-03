import SwiftUI
import VaakyaCore

/// Menu bar menu (plan §7 UI). Panel buttons open AppKit windows via
/// `WindowManager` (AppKit direct — the SwiftUI `openWindow` route from
/// MenuBarExtra content did not work; user feedback 2026-08-02).
/// The status section makes permission gaps and errors visible instead of
/// silent, so "hold-to-talk does nothing" is actionable.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Text("Vaakya \(appVersion)")
            .foregroundStyle(.secondary)
            .onAppear { env.coordinator.refreshPermissions() }

        Divider()

        statusSection

        Divider()

        Button("History") { WindowManager.shared.open("history") }
        Button("Dictionary") { WindowManager.shared.open("dictionary") }
        Button("Onboarding / Permissions") { WindowManager.shared.open("onboarding") }
        Button("Settings…") { WindowManager.shared.open("settings") }

        Divider()
        Button("Re-check permissions") {
            env.coordinator.refreshPermissions()
        }
        Divider()
        Button("Quit Vaakya") { NSApp.terminate(nil) }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? VaakyaCore.version
    }

    @ViewBuilder
    private var statusSection: some View {
        switch env.coordinator.state.phase {
        case .idle:
            Text("Hold Left Option to dictate")
                .foregroundStyle(.secondary)
        case .recording:
            Label("Recording…", systemImage: "record.circle")
                .foregroundStyle(.red)
        case .transcribing:
            Label("Transcribing…", systemImage: "waveform")
                .foregroundStyle(.secondary)
        }

        // Actionable status: what's missing, or the last error.
        if env.coordinator.state.phase == .idle, MicRecorder.micStatus != .granted {
            Text(env.coordinator.micStatusText)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        let perms = env.coordinator.permissionSummary
        if !perms.isEmpty {
            Text(perms)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let error = env.coordinator.state.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if !env.coordinator.hotkeyActive {
            Text("Hotkey inactive — grant Input Monitoring in Onboarding")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if env.coordinator.state.pendingSuggestionCount > 0 {
            Text("\(env.coordinator.state.pendingSuggestionCount) suggestion(s) pending approval")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
