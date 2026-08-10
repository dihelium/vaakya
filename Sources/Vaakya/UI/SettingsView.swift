import SwiftUI
import UniformTypeIdentifiers
import VaakyaCore

/// Settings: stage-2, injection, lenses (Codex CLI or OpenAI), dictionary backup.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var stage2 = false
    @State private var injection: String = "auto"
    @State private var doubleTap = true
    @State private var lensEgress = false
    @State private var lensProvider = "openai"
    @State private var lensAPIBase = "http://127.0.0.1:11434/v1"
    @State private var lensModel = "llama3.2"
    @State private var lensCodexPath = ""
    @State private var apiKeyField = ""
    @State private var message: (String, SemanticTone)?
    @State private var codexFound: String?

    var body: some View {
        Form {
            if let message {
                Section {
                    FeedbackMessage(text: message.0, tone: message.1)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Injection method", selection: Binding(get: { injection }, set: { injection = $0; apply() })) {
                    Text("Auto (Unicode events)").tag("auto")
                    Text("Unicode events").tag("unicode")
                    Text("Paste (Cmd+V)").tag("paste")
                }
                Toggle("Double-tap to latch recording", isOn: Binding(get: { doubleTap }, set: { doubleTap = $0; apply() }))
            } header: {
                Text("Dictation")
            } footer: {
                Text("Hotkey is Left Option in v1. Hold to dictate into any app; double-tap latches until you press again.")
            }

            Section {
                Toggle("Stage 2 — on-device LLM cleanup",
                       isOn: Binding(get: { stage2 }, set: { stage2 = $0; apply() }))
            } header: {
                Text("Personalization")
            } footer: {
                Text("Fixes punctuation and casing using your dictionary. May use Apple Foundation Models, which can route through Private Cloud Compute. Off until you enable it.")
            }

            Section {
                Toggle("Enable AI lenses (opt-in)",
                       isOn: Binding(get: { lensEgress }, set: { lensEgress = $0; apply() }))

                Picker("Lens engine", selection: Binding(get: { lensProvider }, set: { lensProvider = $0; apply() })) {
                    Text("Codex CLI").tag("codex")
                    Text("OpenAI-compatible API").tag("openai")
                }
                .pickerStyle(.radioGroup)

                if lensProvider == "codex" {
                    TextField("Optional path to codex binary", text: Binding(get: { lensCodexPath }, set: { lensCodexPath = $0; apply() }))
                    HStack {
                        if let codexFound {
                            Badge(title: "Found", systemImage: "checkmark.circle.fill", tone: .success)
                            Text(codexFound)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Badge(title: "Not found", systemImage: "exclamationmark.triangle.fill", tone: .warning)
                            Text("Install Codex CLI or set the path.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Re-detect") { refreshCodex() }
                            .controlSize(.small)
                    }
                } else {
                    TextField("API base URL", text: Binding(get: { lensAPIBase }, set: { lensAPIBase = $0; apply() }))
                    TextField("Model", text: Binding(get: { lensModel }, set: { lensModel = $0; apply() }))
                    SecureField("API key (Keychain)", text: $apiKeyField)
                    HStack {
                        Button("Save API key") { saveKey() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        if KeychainStore.load(account: "openai_lens") != nil {
                            Button("Clear key", role: .destructive) {
                                KeychainStore.delete(account: "openai_lens")
                                apiKeyField = ""
                                message = ("API key removed from Keychain.", .success)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Lenses")
            } footer: {
                Text("Local is the safe default. Audio never leaves this Mac. Codex and remote API runs send transcript text only after confirmation. Codex uses this Mac's signed-in account. Available: technical interview notes, self-debrief, strict decisions, strict actions, and local raw transcript copy.")
            }

            Section {
                Button("Export dictionary…") { export() }
                Button("Import dictionary…") { importDict() }
            } header: {
                Text("Data")
            } footer: {
                Text("One JSON file with vocabulary and rules — backup and move-to-a-new-Mac story.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 660)
        .background(VaakyaSurface.canvas)
        .scrollContentBackground(.hidden)
        .onAppear {
            stage2 = env.config.stage2Enabled
            injection = env.config.injectionMethod
            doubleTap = env.config.doubleTapEnabled
            lensEgress = env.config.lensEgressEnabled
            lensProvider = env.config.lensProvider
            lensAPIBase = env.config.lensAPIBase
            lensModel = env.config.lensModel
            lensCodexPath = env.config.lensCodexPath
            refreshCodex()
        }
    }

    private func refreshCodex() {
        codexFound = CodexLensClient.resolveCodexPath(
            configPath: lensCodexPath.isEmpty ? nil : lensCodexPath)
    }

    private func apply() {
        env.coordinator.stage2Gate.set(stage2)
        env.config.stage2Enabled = stage2
        env.config.injectionMethod = injection
        env.config.doubleTapEnabled = doubleTap
        env.config.lensEgressEnabled = lensEgress
        env.config.lensProvider = lensProvider
        env.config.lensAPIBase = lensAPIBase.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.lensModel = lensModel.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.lensCodexPath = lensCodexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        // Map legacy picker into shared runner triad.
        if lensProvider == "codex" {
            env.config.selectedLLMRunner = "codex"
        } else if LocalEndpointPolicy.isAllowedLocalBaseURL(env.config.lensAPIBase) {
            env.config.selectedLLMRunner = "local"
            env.config.localBaseURL = env.config.lensAPIBase
            env.config.localModel = env.config.lensModel
        } else {
            env.config.selectedLLMRunner = "remote"
            env.config.remoteBaseURL = env.config.lensAPIBase
            env.config.remoteModel = env.config.lensModel
        }
        env.config.syncLegacyMirrors()
        env.saveConfig()
        refreshCodex()
    }

    private func saveKey() {
        let trimmed = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = ("Enter a non-empty API key.", .warning)
            return
        }
        do {
            try KeychainStore.save(account: "openai_lens", secret: trimmed)
            apiKeyField = ""
            message = ("API key saved to Keychain.", .success)
        } catch {
            message = ("Keychain save failed: \(error.localizedDescription)", .danger)
        }
    }

    private func export() {
        guard let snapshot = try? DictionaryExporter.snapshot(from: env.db),
              let data = try? DictionaryExporter.encode(snapshot) else {
            message = ("Could not build dictionary export.", .danger)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vaakya-dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: [.atomic])
            message = ("Exported to \(url.lastPathComponent)", .success)
        } catch {
            message = ("Export failed: \(error.localizedDescription)", .danger)
        }
    }

    private func importDict() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? DictionaryExporter.decode(data) else {
            message = ("Could not read dictionary JSON.", .danger)
            return
        }
        do {
            try DictionaryExporter.importSnapshot(snapshot, into: env.db)
            message = ("Imported \(snapshot.rules.count) rule(s), \(snapshot.entries.count) term(s).", .success)
            env.coordinator.refreshBadge()
        } catch {
            message = ("Import failed: \(error.localizedDescription)", .danger)
        }
    }
}
