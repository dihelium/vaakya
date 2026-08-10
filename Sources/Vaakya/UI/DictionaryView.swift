import SwiftUI
import UniformTypeIdentifiers
import VaakyaCore

/// Dictionary / vocabulary: approve suggestions, conflicts, manual rules.
/// Styled to match the Yap shell; Esc / back returns via ShellRouter stack.
struct DictionaryView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared

    @State private var rules: [ReplacementRuleRecord] = []
    @State private var conflictingRuleIDs: Set<Int64> = []
    @State private var entries: [DictionaryEntryRecord] = []
    @State private var seedMessage: (String, SemanticTone)?
    @State private var newMatch = ""
    @State private var newReplacement = ""
    @State private var loadError: String?

    private var suggestedRules: [ReplacementRuleRecord] {
        rules.filter { $0.status == "suggested" }
    }
    private var otherRules: [ReplacementRuleRecord] {
        rules.filter { $0.status != "suggested" }
    }
    private var suggestedEntries: [DictionaryEntryRecord] {
        entries.filter { $0.status == "suggested" }
    }
    private var otherEntries: [DictionaryEntryRecord] {
        entries.filter { $0.status != "suggested" }
    }

    private var backLabel: String {
        if router.backStack.last == .settings { return "settings" }
        return "back"
    }

    private var dictionaryCrumbs: [(String, (() -> Void)?)] {
        var crumbs: [(String, (() -> Void)?)] = [
            ("vaakya", { router.go(.home) }),
        ]
        if router.backStack.last == .settings {
            crumbs.append(("settings", { router.goBack() }))
        }
        crumbs.append(("vocabulary", nil))
        return crumbs
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(YapTheme.hairline).frame(height: 1)

            if let loadError {
                FeedbackMessage(text: loadError, tone: .danger)
                    .padding(20)
            }
            if let seedMessage {
                FeedbackMessage(text: seedMessage.0, tone: seedMessage.1)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            addRuleBar
            Rectangle().fill(YapTheme.hairline).frame(height: 1)

            if rules.isEmpty && entries.isEmpty && loadError == nil {
                VStack(spacing: 12) {
                    Spacer()
                    Text("empty dictionary")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.55))
                    Text("Add a rule above, seed from writing samples, or correct dictations in History.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !suggestedRules.isEmpty {
                            sectionLabel("Suggested rules (\(suggestedRules.count))")
                            ForEach(suggestedRules, id: \.id) { rule in
                                ruleCard(rule)
                            }
                        }

                        sectionLabel("All rules (\(otherRules.count))")
                        if otherRules.isEmpty {
                            Text("No active or disabled rules yet.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        } else {
                            ForEach(otherRules, id: \.id) { rule in
                                ruleCard(rule)
                            }
                        }

                        if !suggestedEntries.isEmpty {
                            sectionLabel("Suggested vocabulary (\(suggestedEntries.count))")
                            ForEach(suggestedEntries, id: \.id) { e in
                                entryCard(e)
                            }
                        }

                        sectionLabel("Vocabulary (\(otherEntries.count))")
                        if otherEntries.isEmpty {
                            Text("No vocabulary terms yet.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        } else {
                            ForEach(otherEntries, id: \.id) { e in
                                entryCard(e)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(YapTheme.canvas)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                YapBreadcrumb(crumbs: dictionaryCrumbs)
                Text("approve suggestions so they reshape future dictation")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
            Spacer()
            HStack(spacing: 14) {
                Button("Seed from samples…") { seedFromFiles() }
                    .buttonStyle(.bordered)
                Button {
                    router.goBack()
                } label: {
                    Text(backLabel)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(YapTheme.coral)
                }
                .buttonStyle(.plain)
                .help("Return to \(backLabel) (Esc)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var addRuleBar: some View {
        HStack(spacing: 12) {
            TextField("Heard as…", text: $newMatch)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            Image(systemName: "arrow.right")
                .foregroundStyle(Color.primary.opacity(0.3))
            TextField("Should be…", text: $newReplacement)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            Button("Add rule") {
                addManualRule()
            }
            .buttonStyle(.borderedProminent)
            .tint(YapTheme.coral)
            .disabled(newMatch.trimmingCharacters(in: .whitespaces).isEmpty
                      || newReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(Color.primary.opacity(0.38))
            .padding(.top, 4)
    }

    private func ruleCard(_ rule: ReplacementRuleRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(rule.match)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.3))
                Text(rule.replacement)
                    .font(.system(size: 16, design: .monospaced))
                Spacer()
                Badge(title: rule.status, tone: SemanticTone.forStatus(rule.status))
                if let id = rule.id, conflictingRuleIDs.contains(id) {
                    Badge(title: "conflict", systemImage: "exclamationmark.triangle.fill", tone: .danger)
                }
            }
            HStack(spacing: 10) {
                Text("\(rule.matchKind) · \(rule.source)")
                Text("seen \(rule.occurrences)× · applied \(rule.hits)×")
                Spacer()
                if rule.status == "suggested" {
                    Button("Approve") { set(rule, "active") }
                        .buttonStyle(.borderedProminent)
                        .tint(YapTheme.coral)
                        .controlSize(.small)
                    Button("Reject", role: .destructive) { set(rule, "disabled") }
                        .controlSize(.small)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.42))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func entryCard(_ e: DictionaryEntryRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.term).font(.system(size: 16, weight: .semibold))
                Text("\(e.kind) · \(e.source) · seen \(e.timesSeen)×")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
            Spacer()
            Badge(title: e.status, tone: SemanticTone.forStatus(e.status))
            if e.status == "suggested" {
                Button("Approve") { setEntry(e, "active") }
                    .buttonStyle(.borderedProminent)
                    .tint(YapTheme.coral)
                    .controlSize(.small)
                Button("Reject", role: .destructive) { setEntry(e, "disabled") }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(YapTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func addManualRule() {
        let m = newMatch.trimmingCharacters(in: .whitespaces)
        let r = newReplacement.trimmingCharacters(in: .whitespaces)
        guard !m.isEmpty, !r.isEmpty else { return }
        do {
            try env.db.upsertReplacementRule(
                ReplacementRule(match: m, replacement: r),
                source: "manual", status: "active")
            newMatch = ""
            newReplacement = ""
            seedMessage = ("Added active rule.", .success)
            reload()
        } catch {
            seedMessage = (error.localizedDescription, .danger)
        }
    }

    private func set(_ rule: ReplacementRuleRecord, _ status: String) {
        guard let id = rule.id else { return }
        do {
            try env.db.setRuleStatus(id: id, status: status)
            reload()
        } catch {
            seedMessage = (error.localizedDescription, .danger)
        }
    }

    private func setEntry(_ e: DictionaryEntryRecord, _ status: String) {
        guard let id = e.id else { return }
        do {
            try env.db.setEntryStatus(id: id, status: status)
            reload()
        } catch {
            seedMessage = (error.localizedDescription, .danger)
        }
    }

    private func reload() {
        do {
            rules = try env.db.rules()
            conflictingRuleIDs = try env.db.conflictingRuleIDs()
            entries = try env.db.dictionaryEntries()
            loadError = nil
            env.coordinator.refreshBadge()
        } catch {
            loadError = error.localizedDescription
        }
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
        do {
            for c in candidates {
                try env.db.upsertDictionaryEntry(
                    term: c.term, kind: c.kind.rawValue,
                    source: "seeded_corpus", status: "suggested",
                    timesSeen: c.timesSeen)
            }
            if candidates.isEmpty {
                seedMessage = ("No vocabulary candidates found in the selected files.", .warning)
            } else {
                seedMessage = ("Seeded \(candidates.count) candidate(s) — approve them below.", .success)
            }
            reload()
        } catch {
            seedMessage = (error.localizedDescription, .danger)
        }
    }
}
