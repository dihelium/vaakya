import SwiftUI
import VaakyaCore

/// History panel (plan 5.5): list dictations, edit-save → corrections row +
/// active rules via DiffLearner (explicit learning path).
struct HistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var dictations: [DictationRecord] = []
    @State private var editingID: Int64?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.title2.bold())
            Text("Editing a transcript teaches Vaakya — the diff becomes an active rule.")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach(dictations, id: \.id) { d in
                    if d.id == editingID {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $draft)
                                .font(.body)
                                .frame(minHeight: 48)
                            HStack {
                                Button("Save & Learn") { save(d) }
                                Button("Cancel") { editingID = nil }
                            }
                        }
                        .padding(4)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.finalText ?? d.rawText ?? "—")
                                .textSelection(.enabled)
                            HStack {
                                Text(d.timestamp).font(.caption2).foregroundStyle(.secondary)
                                if d.llmCleaned {
                                    Text("LLM").font(.caption2).foregroundStyle(.purple)
                                }
                                if d.rawText != d.finalText {
                                    Text("raw: \(d.rawText ?? "")")
                                        .font(.caption2).foregroundStyle(.orange).lineLimit(1)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingID = d.id
                            draft = d.finalText ?? d.rawText ?? ""
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 400)
        .onAppear { reload() }
        .onChange(of: editingID) { reload() }
    }

    private func save(_ d: DictationRecord) {
        guard let id = d.id else { return }
        try? env.db.updateDictationFinalText(id: id, finalText: draft)
        // Explicit edit → corrections row + ACTIVE rules (plan §4 trust policy).
        _ = try? env.db.insertCorrection(dictationId: id,
                                         asrText: d.rawText ?? "",
                                         editedText: draft,
                                         capture: "explicit_history")
        let result = DiffLearner.diff(asrText: d.finalText ?? d.rawText ?? "", editedText: draft)
        for candidate in result.candidates where !result.isWholesaleRewrite {
            try? env.db.upsertReplacementRule(
                ReplacementRule(match: candidate.match,
                                replacement: candidate.replacement,
                                matchKind: candidate.matchKind),
                source: "learned_explicit",
                status: "active")
        }
        env.coordinator.refreshBadge()
        editingID = nil
        reload()
    }

    private func reload() {
        dictations = (try? env.db.dictations(limit: 200)) ?? []
    }
}
