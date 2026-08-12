import SwiftUI
import UniformTypeIdentifiers
import VaakyaCore

/// YapYap-style preferences: pipeline / library / app rail + lenses cards.
struct YapSettingsShellView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared

    @State private var stage2 = false
    @State private var injection = "auto"
    @State private var doubleTap = true
    @State private var lensEgress = false
    @State private var selectedRunner = "local"
    @State private var localBaseURL = "http://127.0.0.1:11434/v1"
    @State private var localModel = "llama3.2"
    @State private var remoteBaseURL = "https://api.openai.com/v1"
    @State private var remoteModel = "gpt-4o"
    @State private var lensCodexPath = ""
    @State private var apiKeyField = ""
    @State private var message: (String, SemanticTone)?
    @State private var codexFound: String?
    @State private var lensFilter = ""
    @State private var lensesTab: LensesTab = .installed
    @State private var bundledLenses: [LensSpec] = []
    @State private var editorMode: CustomLensEditorSheet.Mode?
    @State private var confirmDelete: LensSpec?

    private enum LensesTab: String {
        case installed
        case discover
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            Rectangle().fill(YapTheme.hairline).frame(width: 1)
            rail
                .frame(width: 228)
        }
        .background(YapTheme.canvas)
        .tint(YapTheme.coral)
        .onAppear {
            stage2 = env.config.stage2Enabled
            injection = env.config.injectionMethod
            doubleTap = env.config.doubleTapEnabled
            lensEgress = env.config.lensEgressEnabled
            selectedRunner = env.config.selectedLLMRunner
            localBaseURL = env.config.localBaseURL
            localModel = env.config.localModel
            remoteBaseURL = env.config.remoteBaseURL
            remoteModel = env.config.remoteModel
            lensCodexPath = env.config.lensCodexPath
            refreshCodex()
            bundledLenses = (try? env.lensService.availableLenses()) ?? []
        }
        .sheet(item: $editorMode) { mode in
            CustomLensEditorSheet(
                mode: mode,
                onSave: { id, title, body in
                    try env.lensService.saveCustomLens(id: id, title: title, body: body)
                },
                onCancel: { editorMode = nil },
                onSaved: { spec in
                    refreshLenses()
                    editorMode = nil
                    message = ("Saved \(spec.title).", .success)
                }
            )
        }
        .confirmationDialog(
            "Delete this lens?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete lens", role: .destructive) {
                if let confirmDelete {
                    deleteCustom(confirmDelete)
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("The prompt file is removed. Saved drafts on past recordings stay on disk.")
        }
    }

    // MARK: - Main

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                YapBreadcrumb(crumbs: [
                    ("vaakya", { router.popToRoot() }),
                    ("settings", nil),
                    (router.settingsSection.label, nil),
                ])
                Spacer()
                if router.settingsSection == .lenses {
                    Button {
                        editorMode = .create
                    } label: {
                        Text("+ Create lens")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Write a custom prompt that runs on completed transcripts")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 8)

            Text("your pipeline · your lenses · your archive")
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.horizontal, 28)
                .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message {
                        FeedbackMessage(text: message.0, tone: message.1)
                    }
                    sectionBody
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            railGroup("pipeline", ShellRouter.SettingsSection.pipeline)
            railGroup("library", ShellRouter.SettingsSection.library)
            railGroup("app", ShellRouter.SettingsSection.app)

            Spacer()

            YapTextLink(title: "back") {
                router.goBack()
            }
            .padding(20)
            .yapHoverClick()
        }
        .padding(.top, 24)
        .background(YapTheme.sidebar)
    }

    private func railGroup(_ title: String, _ sections: [ShellRouter.SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            YapTheme.sectionLabel(title)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 8)
            ForEach(sections) { section in
                YapRailItem(
                    title: section.label,
                    selected: router.settingsSection == section
                        || (section == .dictionary && router.destination == .dictionary)
                ) {
                    if section == .dictionary {
                        router.openVocabularyFromSettings()
                    } else {
                        router.settingsSection = section
                        if router.destination != .settings {
                            router.push(.settings)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var sectionBody: some View {
        switch router.settingsSection {
        case .listen:
            listenSection
        case .recognise:
            recogniseSection
        case .understand:
            understandSection
        case .insight:
            insightSection
        case .lenses:
            lensesSection
        case .dictionary:
            settingsCard(title: "vocabulary") {
                Text("Names and phrase rules learned from your corrections. Full editor opens in Dictionary.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Open dictionary…") { router.openVocabularyFromSettings() }
                    .buttonStyle(.borderedProminent)
                    .tint(YapTheme.coral)
            }
            // Dictionary is a separate destination for the full editor.
            .onAppear {
                // Stay here with summary; deep link still works from rail via openPanelID.
            }
        case .data:
            settingsCard(title: "data") {
                Button("Export dictionary…") { export() }
                Button("Import dictionary…") { importDict() }
                Text("One JSON file with vocabulary and rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .about:
            settingsCard(title: "about") {
                Text("Vaakya \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? VaakyaCore.version)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Private voice workspace for Apple Silicon. Local Parakeet, personal dictionary, optional lenses.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("UI shell inspired by local-first product craft (YapYap-style layout). Not affiliated.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var listenSection: some View {
        settingsCard(title: "listen") {
            Text("Hotkey dictation and meeting capture.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Picker("Injection method", selection: Binding(get: { injection }, set: { injection = $0; apply() })) {
                Text("Auto (Unicode events)").tag("auto")
                Text("Unicode events").tag("unicode")
                Text("Paste (Cmd+V)").tag("paste")
            }
            Toggle("Double-tap to latch recording",
                   isOn: Binding(get: { doubleTap }, set: { doubleTap = $0; apply() }))
            Text("Hotkey is Left Option. Hold to dictate into any app. Meetings use mic + Mac audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recogniseSection: some View {
        settingsCard(title: "recognise") {
            capabilityBlock(
                title: SpeechRecognitionProfile.shared.displayName,
                license: "FluidAudio / Parakeet TDT v2",
                body: SpeechRecognitionProfile.shared.summary,
                detail: "Hotkey, start recording, and imported files · on-device")
            capabilityBlock(
                title: "Speaker diarization",
                license: "FluidAudio offline",
                body: "Names turns after a meeting or import so lenses and Ask can cite who said what.",
                detail: "Separate model consent · offline")
            if !env.config.diarizationModelConsentGiven {
                Button("Allow speaker model download") {
                    env.grantDiarizationConsent()
                    message = ("Speaker model consent saved.", .success)
                }
                .buttonStyle(.borderedProminent)
                .tint(YapTheme.coral)
            }
        }
    }

    private var understandSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("understand")
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            sectionHeading("PUNCTUATION + CASING")
            capabilityBlock(
                title: "Stage 2 · on-device cleanup",
                license: "Apple Foundation Models (optional)",
                body: "Adds periods, commas, and capital letters so transcripts read like writing, not stenography.",
                detail: env.config.stage2Enabled ? "Enabled" : "Off by default · may use Private Cloud Compute")
            Toggle("Enable Stage 2 cleanup",
                   isOn: Binding(get: { stage2 }, set: { stage2 = $0; apply() }))

            sectionHeading("NAMED ENTITIES")
            capabilityBlock(
                title: "Dictionary & replacement rules",
                license: "Local SQLite",
                body: "Learns people, products, and phrases from your corrections so later transcripts stay consistent.",
                detail: "Active rules · pending suggestions in Dictionary")

            sectionHeading("SENTIMENT")
            capabilityBlock(
                title: "Mood tagging",
                license: "—",
                body: "Tags each turn as positive, neutral, or negative so you can scan the mood at a glance.",
                detail: "Not installed · planned",
                muted: true)

            sectionHeading("CROSS-RECORDING SEARCH")
            capabilityBlock(
                title: "Archive Ask · budgeted pack",
                license: "Local",
                body: "Ask across completed recordings with keyword + recency packing. Full FTS5 / embeddings are next.",
                detail: "Available now via Ask · FTS5 roadmap")
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("insight")
                .font(.system(size: 28, weight: .semibold, design: .rounded))

            sectionHeading("DEFAULT MODEL")
            settingsCard(title: "") {
                Text("Reads each transcript and writes what your lenses request: summaries, decisions, actions.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Picker("Runner", selection: Binding(get: { selectedRunner }, set: { selectedRunner = $0; apply() })) {
                    Text("Codex CLI").tag("codex")
                    Text("Local (Ollama / LM Studio)").tag("local")
                    Text("Remote (OpenAI-compatible)").tag("remote")
                }
                .pickerStyle(.radioGroup)
                Toggle("Allow AI text egress (Codex / Remote)",
                       isOn: Binding(get: { lensEgress }, set: { lensEgress = $0; apply() }))

                if selectedRunner == "codex" {
                    TextField("Optional path to codex", text: Binding(get: { lensCodexPath }, set: { lensCodexPath = $0; apply() }))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        if let codexFound {
                            Badge(title: "Found", tone: .success)
                            Text(codexFound).font(.caption).lineLimit(1).truncationMode(.middle)
                        } else {
                            Badge(title: "Not found", tone: .warning)
                        }
                        Spacer()
                        Button("Re-detect") { refreshCodex() }.controlSize(.small)
                    }
                    Text("Uses this Mac's signed-in Codex account. Transcript text is sent only after confirmation. Audio is never attached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedRunner == "local" {
                    TextField("Local base URL (loopback)", text: Binding(get: { localBaseURL }, set: { localBaseURL = $0; apply() }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Local model", text: Binding(get: { localModel }, set: { localModel = $0; apply() }))
                        .textFieldStyle(.roundedBorder)
                    Text("Installed locally — e.g. Ollama \(localModel.isEmpty ? "model" : localModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Remote base URL (https)", text: Binding(get: { remoteBaseURL }, set: { remoteBaseURL = $0; apply() }))
                        .textFieldStyle(.roundedBorder)
                    TextField("Remote model", text: Binding(get: { remoteModel }, set: { remoteModel = $0; apply() }))
                        .textFieldStyle(.roundedBorder)
                    SecureField("API key (Keychain)", text: $apiKeyField)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save API key") { saveKey() }
                            .buttonStyle(.borderedProminent)
                            .tint(YapTheme.coral)
                        if KeychainStore.load(account: "openai_lens") != nil {
                            Button("Clear key", role: .destructive) {
                                KeychainStore.delete(account: "openai_lens")
                                apiKeyField = ""
                                message = ("API key removed.", .success)
                            }
                        }
                    }
                }
            }

            sectionHeading("TITLE GENERATION")
            capabilityBlock(
                title: "Recording titles",
                license: "Uses default model",
                body: "Names a recording so you can recognise it weeks later — specific subject, people, decision — grounded only in the transcript.",
                detail: "Planned for job list · uses same runner as lenses when enabled",
                muted: true)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: - Lenses (YAP card list)

    private var lensesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Installed · N | Discover segmented control
            HStack(spacing: 0) {
                lensesTabButton(.installed, count: filteredLenses.count)
                lensesTabButton(.discover, count: nil)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.2)
            )
            .frame(maxWidth: 280)

            // Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.primary.opacity(0.35))
                TextField("Filter your lenses…", text: $lensFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1.2)
            )

            if lensesTab == .installed {
                if filteredLenses.isEmpty {
                    Text("No lenses match.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(filteredLenses.enumerated()), id: \.element.id) { index, lens in
                            lensCard(lens, hotkey: index + 1)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Discover")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("A public catalog is not wired yet. Create your own under Installed — they appear on every completed transcript.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var filteredLenses: [LensSpec] {
        let q = lensFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return bundledLenses }
        return bundledLenses.filter {
            $0.title.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    private func lensesTabButton(_ tab: LensesTab, count: Int?) -> some View {
        let selected = lensesTab == tab
        return Button {
            lensesTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab == .installed ? "Installed" : "Discover")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let count, tab == .installed {
                    Text("·")
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? YapTheme.coral : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .yapHoverClick()
    }

    private func lensCard(_ lens: LensSpec, hotkey: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(lens.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("⌘ \(hotkey)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                HStack(spacing: 8) {
                    Text(lensVersionLabel(lens))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.42))
                    Text(lens.isCustom ? "by you" : "by vaakya")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.42))
                    Image(systemName: lens.isCustom ? "pencil.circle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(YapTheme.coral.opacity(0.85))
                }
                Text(lens.requiresLLM ? "AI lens · \(lens.defaultEgress) default egress" : "Local · no model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            Spacer()
            Menu {
                Button("Show prompt body") {
                    message = (String(lens.body.prefix(400)) + (lens.body.count > 400 ? "…" : ""), .info)
                }
                Button("Copy lens id") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lens.id, forType: .string)
                    message = ("Copied \(lens.id)", .success)
                }
                if lens.isCustom {
                    Divider()
                    Button("Edit lens…") { editorMode = .edit(lens) }
                    Button("Delete lens…", role: .destructive) { confirmDelete = lens }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1.2)
        )
        .yapHoverClick()
    }

    private func lensVersionLabel(_ lens: LensSpec) -> String {
        // Surface a stable-looking version from id prefix.
        if lens.id.hasPrefix("L0") { return "v1.0.0" }
        if lens.id.hasPrefix("L1") { return "v0.2.0" }
        if lens.id.hasPrefix("L2") { return "v0.4.0" }
        if lens.id.hasPrefix("L5b") { return "v0.3.1" }
        if lens.id.hasPrefix("L5") { return "v0.3.0" }
        return "v0.1.0"
    }

    // MARK: - Shared chrome

    private func sectionHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(Color.primary.opacity(0.38))
            .padding(.top, 8)
    }

    private func capabilityBlock(title: String, license: String, body: String,
                                 detail: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text(license)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(muted ? 0.45 : 0.72))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.38))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YapTheme.card.opacity(muted ? 0.6 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .opacity(muted ? 0.85 : 1)
        .yapHoverClick()
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .tracking(-0.3)
            }
            content()
        }
        .padding(title.isEmpty ? 18 : 24)
        .frame(maxWidth: 720, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(YapTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func refreshLenses() {
        bundledLenses = (try? env.lensService.availableLenses()) ?? []
    }

    private func deleteCustom(_ lens: LensSpec) {
        do {
            try env.lensService.deleteCustomLens(id: lens.id)
            refreshLenses()
            message = ("Deleted \(lens.title).", .success)
        } catch {
            message = (error.localizedDescription, .danger)
        }
        confirmDelete = nil
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
        env.config.selectedLLMRunner = selectedRunner
        env.config.localBaseURL = localBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.localModel = localModel.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.remoteBaseURL = remoteBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.remoteModel = remoteModel.trimmingCharacters(in: .whitespacesAndNewlines)
        env.config.lensCodexPath = lensCodexPath.trimmingCharacters(in: .whitespacesAndNewlines)
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
            message = (error.localizedDescription, .danger)
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
            message = (error.localizedDescription, .danger)
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
            message = (error.localizedDescription, .danger)
        }
    }
}

/// Settings rail row with YapYap-style hover fill + click on every hover enter.
private struct YapRailItem: View {
    let title: String
    var selected: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(selected || hovering ? 0.92 : 0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.10 : hovering ? 0.07 : 0))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .yapHoverClick()
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
    }
}
