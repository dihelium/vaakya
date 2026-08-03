import SwiftUI
import UniformTypeIdentifiers
import VaakyaCore

/// Settings (plan 4.4): stage-2 toggle, injection method, hotkey, double-tap,
/// launch-at-login, and dictionary export/import (backup / move machines).
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var stage2 = false // matches the default; onAppear loads persisted value
    @State private var injection: String = "auto"
    @State private var doubleTap = true
    @State private var message: String?

    var body: some View {
        Form {
            Section("Personalization") {
                Toggle("Stage 2 — on-device LLM cleanup (when available)",
                       isOn: Binding(get: { stage2 }, set: { stage2 = $0; apply() }))
                Text("Fixes punctuation/casing using your dictionary as authoritative spellings. "
                     + "May use Apple's Foundation Models, which can route through Apple's Private "
                     + "Cloud Compute — OFF until you enable it here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Picker("Injection method", selection: Binding(get: { injection }, set: { injection = $0; apply() })) {
                    Text("Auto (Unicode events)").tag("auto")
                    Text("Unicode events").tag("unicode")
                    Text("Paste (Cmd+V)").tag("paste")
                }
                Toggle("Double-tap to latch", isOn: Binding(get: { doubleTap }, set: { doubleTap = $0; apply() }))
                Text("Hotkey is fixed at Left Option in v1.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Export dictionary…") { export() }
                Button("Import dictionary…") { importDict() }
                Text("Export writes one JSON file with your vocabulary + rules — your backup and move-to-a-new-Mac story.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
        .onAppear {
            stage2 = env.config.stage2Enabled
            injection = env.config.injectionMethod
            doubleTap = env.config.doubleTapEnabled
        }
    }

    private func apply() {
        env.coordinator.stage2Gate.set(stage2)
        env.config.stage2Enabled = stage2
        env.config.injectionMethod = injection
        env.config.doubleTapEnabled = doubleTap
        env.saveConfig()
    }

    private func export() {
        guard let snapshot = try? DictionaryExporter.snapshot(from: env.db),
              let data = try? DictionaryExporter.encode(snapshot) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vaakya-dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: [.atomic])
            message = "Exported to \(url.lastPathComponent)"
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importDict() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? DictionaryExporter.decode(data) else { return }
        do {
            try DictionaryExporter.importSnapshot(snapshot, into: env.db)
            message = "Imported \(snapshot.rules.count) rule(s), \(snapshot.entries.count) term(s)"
            env.coordinator.refreshBadge()
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
