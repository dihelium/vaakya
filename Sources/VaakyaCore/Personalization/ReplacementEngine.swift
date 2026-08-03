import Foundation

/// How a replacement rule matches text. Mirrors `replacement_rules.match_kind` (plan §4).
public enum RuleMatchKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// Single-token, case-insensitive match. Capitalization of the matched span is preserved.
    case exactCI = "exact_ci"
    /// Single-token, case-sensitive match. Replacement is applied verbatim.
    case exactCS = "exact_cs"
    /// Multi-token phrase, case-insensitive match. Replacement applied verbatim.
    case phrase
}

/// A deterministic misrecognition → correction rule (plan §5.1).
public struct ReplacementRule: Codable, Sendable, Equatable {
    public var match: String
    public var replacement: String
    public var matchKind: RuleMatchKind

    public init(match: String, replacement: String, matchKind: RuleMatchKind = .exactCI) {
        self.match = match
        self.replacement = replacement
        self.matchKind = matchKind
    }
}

/// Stage 1 of the personalization pipeline: deterministic token-level replacement.
///
/// Semantics (plan §5.1):
/// - `exact_ci`: case-insensitive single-token match; the matched span's capitalization
///   pattern is carried onto the replacement (`VAKYA`→`VAAKYA`, `Vakya`→`Vaakya`).
/// - `exact_cs`: verbatim single-token match; replacement applied as stored.
/// - `phrase`: case-insensitive multi-token match; longest-match-first when phrases overlap.
/// - Surrounding punctuation and whitespace are preserved.
///
/// Pure function `(String, [ReplacementRule]) -> String` — no I/O, fully testable.
public enum ReplacementEngine {
    public static func apply(_ text: String, rules: [ReplacementRule]) -> String {
        guard !rules.isEmpty, !text.isEmpty else { return text }

        // Pre-index rules for fast lookup.
        let ciIndex: [String: [ReplacementRule]] = Dictionary(grouping: rules.filter { $0.matchKind == .exactCI }) { $0.match.lowercased() }
        let csIndex: [String: [ReplacementRule]] = Dictionary(grouping: rules.filter { $0.matchKind == .exactCS }) { $0.match }
        let phraseRules: [ReplacementRule] = rules.filter { $0.matchKind == .phrase }
            .sorted { $0.match.split(whereSeparator: \.isWhitespace).count > $1.match.split(whereSeparator: \.isWhitespace).count }

        let words = splitIntoWords(text)
        let trailingWhitespace = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        var core: [String] = []
        var prefix: [String] = []
        var suffix: [String] = []
        var separators: [String] = []
        for w in words {
            prefix.append(w.prefix)
            core.append(w.core)
            suffix.append(w.suffix)
            separators.append(w.precedingSeparator)
        }
        guard !words.isEmpty else { return text }

        let n = core.count
        var i = 0
        var result = ""
        while i < n {
            // Find the best rule starting at token i.
            var best: ReplacementRule?
            var bestSpan = 0

            func consider(_ r: ReplacementRule, _ span: Int) {
                if span > bestSpan {
                    best = r
                    bestSpan = span
                } else if span == bestSpan {
                    // Specificity tie-break: exact_cs > exact_ci > phrase.
                    if let b = best, specificity(r.matchKind) > specificity(b.matchKind) {
                        best = r
                        bestSpan = span
                    }
                }
            }

            // exact_cs
            if let rulesAt = csIndex[core[i]], let r = rulesAt.first {
                consider(r, 1)
            }
            // exact_ci
            if let rulesAt = ciIndex[core[i].lowercased()], let r = rulesAt.first {
                consider(r, 1)
            }
            // phrase (longest first)
            for r in phraseRules {
                let wordsInPhrase = r.match.split(whereSeparator: \.isWhitespace).map(String.init)
                guard !wordsInPhrase.isEmpty else { continue }
                guard i + wordsInPhrase.count <= n else { continue }
                let last = i + wordsInPhrase.count - 1
                let hasInternalPunctuation = (i..<last).contains { !suffix[$0].isEmpty }
                    || ((i + 1)..<(last + 1)).contains { !prefix[$0].isEmpty }
                guard !hasInternalPunctuation else { continue }
                let joined = (i..<(i + wordsInPhrase.count))
                    .map { core[$0].lowercased() }
                    .joined(separator: " ")
                if joined == r.match.lowercased() {
                    consider(r, wordsInPhrase.count)
                    break // longest-first: no shorter phrase can beat this span
                }
            }

            result += separators[i]
            if let r = best {
                let transformed = transform(core: core[i], with: r)
                result += prefix[i] + transformed + suffix[i + bestSpan - 1]
                i += bestSpan
            } else {
                result += prefix[i] + core[i] + suffix[i]
                i += 1
            }
        }
        return result + trailingWhitespace
    }

    // MARK: - internals

    /// Explicit specificity rank for tie-breaks: exact_cs > exact_ci > phrase
    /// on equal match spans (review fix — rawValue ordering was wrong).
    private static func specificity(_ kind: RuleMatchKind) -> Int {
        switch kind {
        case .exactCS: return 3
        case .exactCI: return 2
        case .phrase: return 1
        }
    }

    private struct Word {
        let precedingSeparator: String
        let prefix: String
        let core: String
        let suffix: String
    }

    private static func splitIntoWords(_ text: String) -> [Word] {
        var result: [Word] = []
        var current = ""
        var pendingSeparator = ""
        var startedWord = false

        func flushWord() {
            guard startedWord else { return }
            var prefix = ""
            var coreChars: [Character] = []
            var suffix = ""
            for ch in current {
                if ch.isLetter || ch.isNumber {
                    if suffix.isEmpty {
                        coreChars.append(ch)
                    } else {
                        suffix.append(ch) // letters after a trailing apostrophe stay in the suffix ("vakya's")
                    }
                } else if coreChars.isEmpty {
                    prefix.append(ch)
                } else {
                    suffix.append(ch)
                }
            }
            result.append(Word(precedingSeparator: pendingSeparator,
                               prefix: prefix,
                               core: String(coreChars),
                               suffix: suffix))
            pendingSeparator = ""
            current = ""
            startedWord = false
        }

        for ch in text {
            if ch.isWhitespace {
                flushWord()
                pendingSeparator.append(ch)
            } else {
                current.append(ch)
                startedWord = true
            }
        }
        flushWord()
        return result
    }

    private static func transform(core: String, with rule: ReplacementRule) -> String {
        switch rule.matchKind {
        case .exactCS, .phrase:
            return rule.replacement
        case .exactCI:
            return applyCasePattern(of: core, to: rule.replacement)
        }
    }

    /// Carries the matched span's capitalization pattern onto the replacement.
    private static func applyCasePattern(of input: String, to replacement: String) -> String {
        let hasLower = input.contains { $0.isLowercase }
        let hasUpper = input.contains { $0.isUppercase }
        if hasUpper && !hasLower {
            // ALL CAPS → all caps
            return replacement.uppercased()
        }
        if let first = input.first, first.isUppercase {
            // "Title" → capitalize first char, leave the rest of the replacement as stored
            guard let rFirst = replacement.first else { return replacement }
            return String(rFirst).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
