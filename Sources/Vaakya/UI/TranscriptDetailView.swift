import AppKit
import SwiftUI
import VaakyaCore

private struct TranscriptExportPayload: Codable {
    let speakers: [TranscriptSpeakerRecord]
    let turns: [TranscriptTurnRecord]
}

struct TranscriptDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let jobID: String

    @State private var job: TranscriptionJobRecord?
    @State private var speakers: [TranscriptSpeakerRecord] = []
    @State private var turns: [TranscriptTurnRecord] = []
    @State private var lensRuns: [LensRunRecord] = []
    @State private var lenses: [LensSpec] = []
    @State private var notes: String = ""
    @State private var context: String = ""
    @State private var selectedRunID: String?
    @State private var draftMarkdown: String = ""
    @State private var showRaw = false
    @State private var showNotes = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    /// Which lens id is currently running (nil = idle). Only that row shows a spinner.
    @State private var runningLensID: String?
    @State private var confirmEgressLens: LensSpec?
    @State private var renameSpeaker: TranscriptSpeakerRecord?
    @State private var renameText = ""
    /// Live read-only Codex CLI log (opened automatically when a codex lens runs).
    @State private var codexConsole = CodexConsoleStore()
    @State private var showCodexConsole = false
    /// One-shot extra context entered on the run confirmation sheet.
    @State private var runExtraContext = ""
    @State private var editorMode: CustomLensEditorSheet.Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let job {
                header(job)
                Divider()
                if job.status != "completed" {
                    processingBanner(job)
                }
                if let errorMessage {
                    FeedbackMessage(text: errorMessage, tone: .danger)
                        .padding(.horizontal, VaakyaSpace.lg)
                        .padding(.top, VaakyaSpace.sm)
                }
                if let statusMessage {
                    FeedbackMessage(text: statusMessage, tone: .neutral)
                        .padding(.horizontal, VaakyaSpace.lg)
                        .padding(.top, VaakyaSpace.sm)
                }
                HSplitView {
                    transcriptColumn
                        .frame(minWidth: 320)
                    lensesColumn
                        .frame(minWidth: 300)
                }
            } else {
                ContentUnavailableView {
                    ProgressView()
                } description: {
                    Text("Loading transcript…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(YapTheme.canvas)
        .tint(YapTheme.coral)
        .task(id: jobID) {
            while !Task.isCancelled {
                load()
                if job?.status == "completed" || job?.status == "failed" || job?.status == "cancelled" {
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
            loadLensesAndSidecars()
        }
        .sheet(item: $confirmEgressLens) { lens in
            egressSheet(lens)
        }
        .sheet(item: Binding(
            get: { renameSpeaker.map { SpeakerRenameItem(speaker: $0) } },
            set: { renameSpeaker = $0?.speaker }
        )) { item in
            renameSheet(item.speaker)
        }
        .sheet(isPresented: $showCodexConsole) {
            CodexConsoleView(store: codexConsole) {
                // Keep log text after close; only hide the sheet.
                showCodexConsole = false
            }
        }
        .sheet(item: $editorMode) { mode in
            CustomLensEditorSheet(
                mode: mode,
                onSave: { id, title, body in
                    try env.lensService.saveCustomLens(id: id, title: title, body: body)
                },
                onCancel: { editorMode = nil },
                onSaved: { spec in
                    loadLensesAndSidecars()
                    editorMode = nil
                    statusMessage = "Saved \(spec.title). Run it from the list."
                }
            )
        }
    }

    // MARK: - Header

    private func header(_ job: TranscriptionJobRecord) -> some View {
        HStack(alignment: .center, spacing: VaakyaSpace.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(job.sourceName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: VaakyaSpace.sm) {
                    Badge(title: job.status.capitalized, tone: SemanticTone.forStatus(job.status))
                    Text(metadata(job))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !turns.isEmpty {
                        Text("\(turns.count) turns · \(speakers.count) speakers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !lensRuns.isEmpty {
                        Badge(title: "\(lensRuns.count) draft(s)", systemImage: "doc.text", tone: .info)
                    }
                    Badge(title: SpeechRecognitionProfile.displayName(for: job.asrModel),
                          systemImage: "waveform", tone: .neutral)
                }
            }
            Spacer(minLength: VaakyaSpace.sm)
            if !turns.isEmpty {
                Menu {
                    Button("Copy plain text") { copy(plainText) }
                    Button("Copy Markdown") { copy(markdown) }
                    Divider()
                    Button("Export plain text…") { export(plainText, extension: "txt") }
                    Button("Export Markdown…") { export(markdown, extension: "md") }
                    Button("Export JSON…") { exportJSON() }
                } label: {
                    Label("Copy / Export", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, VaakyaSpace.panelInset)
        .padding(.vertical, VaakyaSpace.xl)
    }

    private func processingBanner(_ job: TranscriptionJobRecord) -> some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.sm) {
            ProgressView(value: job.progress) {
                Text(processingLabel(job))
                    .font(.callout.weight(.medium))
            }
            if let error = job.errorMessage {
                FeedbackMessage(text: error, tone: .danger)
            }
        }
        .padding(VaakyaSpace.xl)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - Transcript column

    private var transcriptColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                Spacer()
                if job?.status == "completed" {
                    Button {
                        showNotes.toggle()
                    } label: {
                        Label(showNotes ? "Hide notes" : "Notes & context",
                              systemImage: showNotes ? "note.text" : "note.text")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, VaakyaSpace.lg)
            .padding(.vertical, VaakyaSpace.md)

            if showNotes {
                notesEditor
                Divider()
            }

            if speakers.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VaakyaSpace.sm) {
                        ForEach(speakers, id: \.speakerKey) { sp in
                            Button {
                                renameText = sp.displayName
                                renameSpeaker = sp
                            } label: {
                                Label(sp.displayName, systemImage: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(speakerColor(sp.speakerKey))
                        }
                    }
                    .padding(.horizontal, VaakyaSpace.lg)
                    .padding(.bottom, VaakyaSpace.sm)
                }
            }

            if turns.isEmpty {
                let terminal = job?.status == "failed" || job?.status == "cancelled"
                ContentUnavailableView(
                    terminal
                        ? (job?.status == "failed" ? "Transcription failed" : "Transcription cancelled")
                        : (job?.status == "completed" ? "No transcript turns" : "Transcript is processing"),
                    systemImage: terminal ? "exclamationmark.triangle" : "waveform")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VaakyaSpace.md) {
                        ForEach(turns, id: \.ordinal) { turn in
                            turnCard(turn)
                        }
                    }
                    .padding(VaakyaSpace.lg)
                }
                Divider()
                DisclosureGroup(isExpanded: $showRaw) {
                    ScrollView {
                        Text(job?.rawText ?? "No raw transcript stored.")
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, VaakyaSpace.sm)
                    }
                    .frame(maxHeight: 120)
                } label: {
                    Label("Raw ASR evidence", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, VaakyaSpace.lg)
                .padding(.vertical, VaakyaSpace.sm)
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.sm) {
            Text("Notes (privileged over transcript)")
                .font(.caption.weight(.semibold))
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(VaakyaSpace.sm)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
            Text("Context pack (names, glossary, do-not-infer)")
                .font(.caption.weight(.semibold))
            TextEditor(text: $context)
                .font(.caption)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(VaakyaSpace.sm)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
            HStack {
                Button("Save notes & context") {
                    do {
                        try env.lensService.saveNotes(jobID: jobID, text: notes)
                        try env.lensService.saveContext(jobID: jobID, text: context)
                        statusMessage = "Saved notes and context."
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Seed interview context") {
                    context = LensCatalog.defaultContextMarkdown()
                }
                .controlSize(.small)
            }
        }
        .padding(VaakyaSpace.lg)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Lenses column

    private var lensesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VaakyaSpace.sm) {
                Text("Lenses")
                    .font(.headline)
                Spacer()
                if runningLensID != nil || !codexConsole.lines.isEmpty {
                    Button {
                        showCodexConsole = true
                    } label: {
                        Label(codexConsole.isRunning ? "Codex log (live)" : "Codex log",
                              systemImage: "terminal")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if runningLensID != nil {
                    ProgressView().controlSize(.small)
                }
                if job?.status == "completed" {
                    Button {
                        editorMode = .create
                    } label: {
                        Label("New lens", systemImage: "plus")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Write a custom prompt for this and future transcripts")
                    .disabled(runningLensID != nil)
                }
            }
            .padding(.horizontal, VaakyaSpace.lg)
            .padding(.vertical, VaakyaSpace.md)

            Text("Run a lens for a draft. Saved drafts mean finished work; a spinner means in progress.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, VaakyaSpace.lg)
                .padding(.bottom, VaakyaSpace.sm)

            if job?.status != "completed" {
                ContentUnavailableView("Finish transcription first", systemImage: "hourglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(lenses, id: \.id) { lens in
                            Button {
                                requestRun(lens)
                            } label: {
                                HStack(alignment: .center, spacing: VaakyaSpace.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lens.title)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text(lensSubtitle(lens))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    lensStatusBadge(for: lens.id)
                                }
                            }
                            .disabled(runningLensID != nil)
                        }
                    } header: {
                        Text("Run lens")
                    } footer: {
                        Text(lensRuns.isEmpty
                             ? "No drafts yet. Choose a lens above to run it."
                             : "\(lensRuns.count) draft(s) saved for this transcript.")
                    }

                    Section("Saved drafts") {
                        if lensRuns.isEmpty {
                            Text("Nothing completed yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(lensRuns, id: \.id) { run in
                            Button {
                                selectRun(run)
                            } label: {
                                HStack(spacing: VaakyaSpace.sm) {
                                    Image(systemName: statusIcon(run.status))
                                        .foregroundStyle(statusColor(run.status))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayTitle(for: run.lensID) + " · v\(run.version)")
                                            .fontWeight(selectedRunID == run.id ? .semibold : .regular)
                                            .foregroundStyle(.primary)
                                        Text("\(run.status) · via \(run.via)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedRunID == run.id {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)

                if !draftMarkdown.isEmpty {
                    Divider()
                    HStack {
                        Text("Draft")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let run = lensRuns.first(where: { $0.id == selectedRunID }) {
                            if run.status == "draft" {
                                Button("Mark reviewed") { promote(run, to: "reviewed") }
                                    .controlSize(.small)
                            }
                            if run.status == "reviewed" {
                                Button("Mark final") { promote(run, to: "final") }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                            Button("Copy") { copy(draftMarkdown) }
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, VaakyaSpace.lg)
                    .padding(.top, VaakyaSpace.sm)
                    ScrollView {
                        Text(draftMarkdown)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(VaakyaSpace.lg)
                    }
                    .frame(minHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                }
            }
        }
        .background(VaakyaSurface.sidebar.opacity(0.55))
    }

    // MARK: - Actions

    private func requestRun(_ lens: LensSpec) {
        errorMessage = nil
        statusMessage = nil
        if !lens.requiresLLM {
            Task { await performRun(lens, allowEgress: false, extraContext: "") }
            return
        }
        let runner = env.config.runnerKind
        if runner == .local {
            if !LocalEndpointPolicy.isAllowedLocalBaseURL(env.config.localBaseURL) {
                errorMessage = "Local runner needs a loopback base URL in Settings → Lenses."
                return
            }
            runExtraContext = ""
            confirmEgressLens = lens
            return
        }
        if !env.config.lensEgressEnabled {
            errorMessage = "Enable AI text egress in Settings → Lenses for Codex/Remote, then try again."
            return
        }
        if runner == .remote {
            if KeychainStore.load(account: "openai_lens")?.isEmpty != false {
                errorMessage = "Add a remote API key in Settings → Lenses."
                return
            }
        } else if CodexLensClient.resolveCodexPath(
            configPath: env.config.lensCodexPath.isEmpty ? nil : env.config.lensCodexPath) == nil {
            errorMessage = "codex CLI not found. Install Codex or set its path in Settings → Lenses."
            return
        }
        // Fresh optional context each confirmation.
        runExtraContext = ""
        confirmEgressLens = lens
    }

    private func egressSheet(_ lens: LensSpec) -> some View {
        let runner = env.config.runnerKind
        let bodyText: String = {
            switch runner {
            case .codex:
                let path = CodexLensClient.resolveCodexPath(
                    configPath: env.config.lensCodexPath.isEmpty ? nil : env.config.lensCodexPath) ?? "codex"
                return "Vaakya will run Codex CLI on this Mac:\n\(path)\n\nIt receives transcript, notes, context pack, and any additional context you enter below in a text-only staging folder. Audio is never attached."
            case .local:
                return "Vaakya will send transcript text to local runner:\n\(env.config.localBaseURL)\nModel: \(env.config.localModel)\n\nLoopback only. Audio never leaves this Mac."
            case .remote:
                return "Vaakya will send transcript, notes, context pack, and any additional context below to:\n\(env.config.remoteBaseURL)\nModel: \(env.config.remoteModel)\n\nAudio never leaves this Mac."
            }
        }()
        return VStack(alignment: .leading, spacing: VaakyaSpace.lg) {
            Text(runner == .local
                 ? "Run “\(lens.title)” with local model?"
                 : runner == .codex
                 ? "Run “\(lens.title)” with Codex CLI?"
                 : "Send transcript text for “\(lens.title)”?")
                .font(.title3.weight(.semibold))
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: VaakyaSpace.sm) {
                Text("Additional context for this run (optional)")
                    .font(.subheadline.weight(.semibold))
                Text("Merged into the prompt for this run only. Not saved to the durable context pack unless you edit Notes & context.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                TextEditor(text: $runExtraContext)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(VaakyaSpace.sm)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: VaakyaRadius.card)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            HStack {
                Button("Cancel") {
                    runExtraContext = ""
                    confirmEgressLens = nil
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(runner == .codex ? "Run with Codex" : runner == .local ? "Run locally" : "Send & run lens") {
                    let extra = runExtraContext
                    confirmEgressLens = nil
                    Task { await performRun(lens, allowEgress: true, extraContext: extra) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(VaakyaSpace.xxl)
        .frame(width: 520)
    }

    private func performRun(_ lens: LensSpec, allowEgress: Bool, extraContext: String) async {
        runningLensID = lens.id
        statusMessage = "Running \(lens.title)… this can take several minutes with Codex."
        errorMessage = nil
        let useCodex = lens.requiresLLM
            && env.config.runnerKind == .codex
            && (env.config.lensEgressEnabled && allowEgress || !env.config.runnerKind.isB1)
        if useCodex {
            let bin = CodexLensClient.resolveCodexPath(
                configPath: env.config.lensCodexPath.isEmpty ? nil : env.config.lensCodexPath)
                ?? "codex"
            codexConsole.begin(
                title: "Codex · \(lens.title)",
                commandSummary: "$ \(bin) exec (ephemeral, tool-disabled, read-only)")
            if !extraContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                codexConsole.appendSystem("$ extra context: \(extraContext.count) chars (included in prompt)")
            }
            showCodexConsole = true
        }
        defer { runningLensID = nil }
        do {
            try env.lensService.saveNotes(jobID: jobID, text: notes)
            try env.lensService.saveContext(jobID: jobID, text: context)
            let run = try await env.lensService.run(
                jobID: jobID,
                lensID: lens.id,
                allowEgress: allowEgress,
                extraContext: extraContext,
                onCodexLog: { chunk in
                    Task { @MainActor in
                        codexConsole.append(chunk)
                    }
                })
            if useCodex {
                codexConsole.finish(success: true, detail: "Draft: \(run.lensID) v\(run.version)")
            }
            load()
            selectRun(run)
            statusMessage = "Done: \(displayTitle(for: run.lensID)) v\(run.version) (\(run.status)). Open it under Saved drafts."
            errorMessage = nil
        } catch {
            if useCodex {
                codexConsole.finish(success: false, detail: error.localizedDescription)
                showCodexConsole = true
            }
            errorMessage = error.localizedDescription
            statusMessage = "Lens did not finish — nothing saved as a draft. Check Codex log if shown."
        }
    }

    /// Latest run for a lens id, if any.
    private func latestRun(for lensID: String) -> LensRunRecord? {
        lensRuns
            .filter { $0.lensID == lensID }
            .max(by: { $0.version < $1.version })
    }

    private func displayTitle(for lensID: String) -> String {
        lenses.first(where: { $0.id == lensID })?.title ?? lensID
    }

    private func lensSubtitle(_ lens: LensSpec) -> String {
        if let run = latestRun(for: lens.id) {
            return "Last: \(run.status) v\(run.version) · \(run.via) — tap to re-run"
        }
        let origin = lens.isCustom ? "Custom · " : ""
        if lens.requiresLLM {
            switch env.config.runnerKind {
            case .codex: return "\(origin)Not run yet · AI via Codex CLI (opt-in)"
            case .local: return "\(origin)Not run yet · AI via local model"
            case .remote: return "\(origin)Not run yet · AI via remote API (opt-in)"
            }
        }
        return "\(origin)Not run yet · Local — copy transcript"
    }

    @ViewBuilder
    private func lensStatusBadge(for lensID: String) -> some View {
        if runningLensID == lensID {
            ProgressView().controlSize(.small)
        } else if let run = latestRun(for: lensID) {
            Badge(title: run.status, systemImage: statusIcon(run.status), tone: SemanticTone.forStatus(run.status))
        } else {
            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not run yet")
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "final": return "checkmark.seal.fill"
        case "reviewed": return "checkmark.circle.fill"
        default: return "doc.text"
        }
    }

    private func statusColor(_ status: String) -> Color {
        SemanticTone.forStatus(status).color
    }

    private func selectRun(_ run: LensRunRecord) {
        selectedRunID = run.id
        do {
            draftMarkdown = try env.lensService.loadMarkdown(run: run)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            draftMarkdown = ""
        }
    }

    private func promote(_ run: LensRunRecord, to status: String) {
        do {
            try env.lensService.promote(runID: run.id, to: status)
            load()
            if let updated = try env.db.lensRun(id: run.id) {
                selectRun(updated)
            }
            statusMessage = "Marked \(run.lensID) v\(run.version) as \(status)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameSheet(_ speaker: TranscriptSpeakerRecord) -> some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.md) {
            Text("Rename speaker")
                .font(.headline)
            Text(speaker.speakerKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Display name", text: $renameText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { renameSpeaker = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    do {
                        try env.db.updateTranscriptSpeakerDisplayName(
                            jobID: jobID,
                            speakerKey: speaker.speakerKey,
                            displayName: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                        renameSpeaker = nil
                        load()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(VaakyaSpace.xl)
        .frame(width: 340)
    }

    // MARK: - Load

    private func load() {
        do {
            job = try env.db.transcriptionJob(id: jobID)
            speakers = try env.db.transcriptSpeakers(jobID: jobID)
            turns = try env.db.transcriptTurns(jobID: jobID)
            lensRuns = try env.db.lensRuns(jobID: jobID)
            env.transcriptionRunner.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadLensesAndSidecars() {
        do {
            lenses = try env.lensService.availableLenses()
            try env.lensService.ensureSidecarFiles(jobID: jobID)
            notes = env.lensService.loadNotes(jobID: jobID)
            context = env.lensService.loadContext(jobID: jobID)
            if let first = lensRuns.first {
                selectRun(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transcript helpers

    private var names: [String: String] {
        Dictionary(uniqueKeysWithValues: speakers.map { ($0.speakerKey, $0.displayName) })
    }

    private var plainText: String {
        TranscriptFormatter.plainText(turns.map(\.asTurn), speakerNames: names)
    }

    private var markdown: String {
        TranscriptFormatter.markdown(turns.map(\.asTurn), speakerNames: names)
    }

    private func speakerName(_ key: String) -> String { names[key] ?? key }

    private func turnCard(_ turn: TranscriptTurnRecord) -> some View {
        HStack(alignment: .top, spacing: VaakyaSpace.md) {
            ZStack {
                Circle().fill(speakerColor(turn.speakerKey).opacity(0.16))
                Image(systemName: turn.speakerKey == SpeakerAttribution.unknownSpeakerKey ? "questionmark" : "person.fill")
                    .font(.caption)
                    .foregroundStyle(speakerColor(turn.speakerKey))
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(speakerName(turn.speakerKey))
                        .fontWeight(.semibold)
                    Spacer()
                    Text(timestamp(turn.startSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                Text(turn.finalText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(VaakyaSpace.lg)
        .background(VaakyaSurface.card, in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: VaakyaRadius.card).strokeBorder(VaakyaSurface.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func speakerColor(_ key: String) -> Color {
        guard key != SpeakerAttribution.unknownSpeakerKey else { return .secondary }
        let palette: [Color] = [.blue, .purple, .orange, .teal, .pink]
        let index = speakers.firstIndex(where: { $0.speakerKey == key }) ?? 0
        return palette[index % palette.count]
    }

    private func processingLabel(_ job: TranscriptionJobRecord) -> String {
        switch job.activeStage {
        case "preparingASR": return "Loading \(SpeechRecognitionProfile.displayName(for: job.asrModel))"
        case "transcribing": return "Transcribing with \(SpeechRecognitionProfile.displayName(for: job.asrModel))"
        case "preparingDiarizer": return "Loading speaker model"
        case "diarizing": return "Identifying speakers"
        case "aligning": return "Building transcript"
        default: return job.status.capitalized
        }
    }

    private func metadata(_ job: TranscriptionJobRecord) -> String {
        let duration = timestamp(job.durationSeconds)
        let megabytes = Double(job.fileSizeBytes) / 1_048_576
        return "\(duration) · \(String(format: "%.1f MB", megabytes)) · \(SpeechRecognitionProfile.displayName(for: job.asrModel))"
    }

    private func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func export(_ text: String, extension fileExtension: String) {
        save(data: Data(text.utf8), extension: fileExtension)
    }

    private func exportJSON() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            save(data: try encoder.encode(TranscriptExportPayload(speakers: speakers, turns: turns)), extension: "json")
        } catch { errorMessage = error.localizedDescription }
    }

    private func save(data: Data, extension fileExtension: String) {
        let panel = NSSavePanel()
        let base = job?.sourceName.split(separator: ".").dropLast().joined(separator: ".") ?? "transcript"
        panel.nameFieldStringValue = "\(base).\(fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: [.atomic]) }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Sheet identity wrapper for speaker rename.
private struct SpeakerRenameItem: Identifiable {
    var id: String { speaker.speakerKey }
    var speaker: TranscriptSpeakerRecord
}

extension LensSpec: Identifiable {}
