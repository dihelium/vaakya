import SwiftUI
import UniformTypeIdentifiers
import VaakyaCore

/// Dictionary panel (plan 3.2 / 5.6): approve/reject suggested rules, view
/// conflicts/occurrences/hits, manual add, and seed from writing samples.
struct DictionaryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var rules: [ReplacementRuleRecord] = []
    @State private var conflictingRuleIDs: Set<Int64> = []
    @State private var entries: [DictionaryEntryRecord] = []
    @State private var seedMessage: String?
    @State private var newMatch = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictionary").font(.title2.bold())

            // Manual add
            HStack(spacing: 8) {
                TextField("heard as…", text: $newMatch)
                    .textFieldStyle(.roundedBorder)
                TextField("should be…", text: $newReplacement)
                    .textFieldStyle(.roundedBorder)
                Button("Add active rule") {
                    let m = newMatch.trimmingCharacters(in: .whitespaces)
                    let r = newReplacement.trimmingCharacters(in: .whitespaces)
                    guard !m.isEmpty, !r.isEmpty else { return }
                    try? env.db.upsertReplacementRule(
                        ReplacementRule(match: m, replacement: r),
                        source: "manual", status: "active")
                    newMatch = ""; newReplacement = ""
                    reload()
                }
                .disabled(newMatch.isEmpty || newReplacement.isEmpty)
            }

            // Seed from writing samples
            HStack(spacing: 8) {
                Button("Seed from writing samples…") { seedFromFiles() }
                if let seedMessage {
                    Text(seedMessage).font(.caption).foregroundStyle(.green).lineLimit(2)
                }
            }

            Divider()

            Text("Replacement rules (\(rules.count))").font(.headline)
            List {
                ForEach(rules, id: \.id) { rule in
                    HStack {
                        Text("\(rule.match) → \(rule.replacement)")
                            .font(.body.monospaced())
                        Text("\(rule.matchKind) · \(rule.source)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("seen \(rule.occurrences)× · hit \(rule.hits)×")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        statusBadge(rule.status)
                        if let id = rule.id, conflictingRuleIDs.contains(id) {
                            Text("conflict")
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                        }
                        if rule.status == "suggested" {
                            Button("Approve") { set(rule, "active") }
                            Button("Reject") { set(rule, "disabled") }
                        }
                    }
                }
            }
            .frame(minHeight: 120)

            Text("Vocabulary (\(entries.count))").font(.headline)
            List {
                ForEach(entries, id: \.id) { e in
                    HStack {
                        Text(e.term)
                        Text("\(e.kind) · \(e.source) · seen \(e.timesSeen)×")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        statusBadge(e.status)
                        if e.status == "suggested" {
                            Button("Approve") { setEntry(e, "active") }
                            Button("Reject") { setEntry(e, "disabled") }
                        }
                    }
                }
            }
            .frame(minHeight: 120)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 560)
        .onAppear { reload() }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(status == "active" ? Color.green.opacity(0.2) :
                        status == "suggested" ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
            .cornerRadius(4)
    }

    private func set(_ rule: ReplacementRuleRecord, _ status: String) {
        guard let id = rule.id else { return }
        try? env.db.setRuleStatus(id: id, status: status)
        reload()
    }

    private func setEntry(_ e: DictionaryEntryRecord, _ status: String) {
        guard let id = e.id else { return }
        try? env.db.setEntryStatus(id: id, status: status)
        reload()
    }

    private func reload() {
        rules = (try? env.db.rules()) ?? []
        conflictingRuleIDs = (try? env.db.conflictingRuleIDs()) ?? []
        entries = (try? env.db.dictionaryEntries()) ?? []
        env.coordinator.refreshBadge()
    }

    private func seedFromFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK else { return }

        var texts: [String] = []
        for url in panel.urls {
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                texts.append(data)
            }
        }
        let candidates = WritingSampleSeeder.candidates(from: texts)
        for c in candidates {
            try? env.db.upsertDictionaryEntry(term: c.term, kind: c.kind.rawValue,
                                              source: "seeded_corpus", status: "suggested",
                                              timesSeen: c.timesSeen)
        }
        seedMessage = "Seeded \(candidates.count) candidate(s) — approve them above."
        reload()
    }
}
