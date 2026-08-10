import SwiftUI
import VaakyaCore

/// Dictation history: edit a row to teach Vaakya via DiffLearner.
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var dictations: [DictationRecord] = []
    @State private var editingID: Int64?
    @State private var draft = ""
    @State private var loadError: String?
    @State private var feedback: (String, SemanticTone)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PanelHeader(
                    title: "History",
                    subtitle: "edit a line to teach Vaakya — the diff becomes an active rule"
                )
                Spacer(minLength: 0)
                Button {
                    ShellRouter.shared.goBack()
                } label: {
                    Text(ShellRouter.shared.backStack.isEmpty ? "home" : "back")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(YapTheme.coral)
                }
                .buttonStyle(.plain)
                .help("Back (Esc)")
                .padding(.trailing, VaakyaSpace.panelInset)
            }
            Rectangle().fill(VaakyaSurface.hairline).frame(height: 1)

            if let loadError {
                FeedbackMessage(text: loadError, tone: .danger)
                    .padding(VaakyaSpace.lg)
            }
            if let feedback {
                FeedbackMessage(text: feedback.0, tone: feedback.1)
                    .padding(.horizontal, VaakyaSpace.lg)
                    .padding(.top, VaakyaSpace.sm)
            }

            if dictations.isEmpty && loadError == nil {
                ContentUnavailableView {
                    Label("No dictations yet", systemImage: "text.bubble")
                } description: {
                    Text("Hold Left Option to dictate. Entries appear here so you can correct and teach Vaakya.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dictations, id: \.id) { d in
                        if d.id == editingID {
                            editRow(d)
                        } else {
                            displayRow(d)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 600, minHeight: 460)
        .background(VaakyaSurface.canvas)
        .onAppear { reload() }
        .onChange(of: editingID) { _, _ in reload() }
    }

    private func displayRow(_ d: DictationRecord) -> some View {
        Button {
            editingID = d.id
            draft = d.finalText ?? d.rawText ?? ""
            feedback = nil
        } label: {
            VStack(alignment: .leading, spacing: VaakyaSpace.sm) {
                Text(d.finalText ?? d.rawText ?? "—")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                HStack(spacing: VaakyaSpace.sm) {
                    Text(d.timestamp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if d.llmCleaned {
                        Badge(title: "LLM", systemImage: "sparkles", tone: .info)
                    }
                    if d.rawText != nil, d.rawText != d.finalText {
                        Badge(title: "Edited", tone: .warning)
                    }
                    Spacer()
                    Text("Edit")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double-click or activate to edit and teach Vaakya")
    }

    private func editRow(_ d: DictationRecord) -> some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.sm) {
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(VaakyaSpace.sm)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: VaakyaRadius.card))

            if let raw = d.rawText, !raw.isEmpty, raw != draft {
                Text("Original ASR: \(raw)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Button("Save & Learn") { save(d) }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel") {
                    editingID = nil
                    feedback = nil
                }
                Spacer()
            }
        }
        .padding(.vertical, VaakyaSpace.sm)
    }

    private func save(_ d: DictationRecord) {
        guard let id = d.id else { return }
        do {
            try env.db.updateDictationFinalText(id: id, finalText: draft)
            _ = try env.db.insertCorrection(
                dictationId: id,
                asrText: d.rawText ?? "",
                editedText: draft,
                capture: "explicit_history")
            let result = DiffLearner.diff(asrText: d.finalText ?? d.rawText ?? "", editedText: draft)
            var learned = 0
            for candidate in result.candidates where !result.isWholesaleRewrite {
                try env.db.upsertReplacementRule(
                    ReplacementRule(match: candidate.match,
                                    replacement: candidate.replacement,
                                    matchKind: candidate.matchKind),
                    source: "learned_explicit",
                    status: "active")
                learned += 1
            }
            env.coordinator.refreshBadge()
            editingID = nil
            feedback = learned > 0
                ? ("Saved. Learned \(learned) active rule(s).", .success)
                : ("Saved. No new rules from this edit.", .neutral)
            reload()
        } catch {
            feedback = (error.localizedDescription, .danger)
        }
    }

    private func reload() {
        do {
            dictations = try env.db.dictations(limit: 200)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            dictations = []
        }
    }
}
