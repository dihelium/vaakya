import AppKit
import SwiftUI
import VaakyaCore

/// Menu bar menu. Actions route into the YapYap-style main shell via WindowManager.
struct MenuBarView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Text("Vaakya \(appVersion)")
            .foregroundStyle(.secondary)
            .onAppear { env.coordinator.refreshPermissions() }

        statusSection

        Divider()

        Button("Show Vaakya") {
            WindowManager.shared.openShell(route: .home)
        }
        Button("Transcribe Audio…") {
            WindowManager.shared.openShell(route: .recordings)
            AudioImportPanel.chooseAndEnqueue(in: env)
        }
        Button("Recordings") {
            WindowManager.shared.openShell(route: .recordings)
        }

        Divider()

        Button("History") { WindowManager.shared.openShell(route: .history) }
        Button("Dictionary") { WindowManager.shared.openShell(route: .dictionary) }

        Divider()

        Button("Onboarding / Permissions") { WindowManager.shared.open("onboarding") }
        Button("Settings…") { WindowManager.shared.openShell(route: .settings) }
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

        if let error = env.coordinator.state.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
        if !env.coordinator.hotkeyActive {
            Text("Hotkey inactive — grant Input Monitoring")
                .font(.caption)
                .foregroundStyle(.orange)
        }
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
                .lineLimit(2)
        }
        if !env.coordinator.state.modelsReady {
            Text("Speech model not ready — open Onboarding")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if env.coordinator.state.pendingSuggestionCount > 0 {
            Text("\(env.coordinator.state.pendingSuggestionCount) suggestion(s) pending in Dictionary")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
