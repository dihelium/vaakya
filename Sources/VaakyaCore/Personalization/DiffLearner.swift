import Foundation

/// A candidate (match → replacement) pair derived from a user edit (plan §5.3).
public struct DiffCandidate: Equatable, Sendable {
    public let match: String
    public let replacement: String
    public let matchKind: RuleMatchKind
    /// Number of tokens in the substitution span (1 for exact rules, >1 for phrase).
    public let spanTokens: Int

    public init(match: String, replacement: String, matchKind: RuleMatchKind, spanTokens: Int) {
        self.match = match
        self.replacement = replacement
        self.matchKind = matchKind
        self.spanTokens = spanTokens
    }
}

/// Result of diffing ASR/injected text against the user's edited text.
public struct DiffResult: Equatable, Sendable {
    public let candidates: [DiffCandidate]
    public let substitutionCount: Int
    public let insertionCount: Int
    public let deletionCount: Int
    /// Number of tokens in the ASR (original) text.
    public let asrTokenCount: Int
    /// Number of tokens in the edited (reference) text.
    public let editedTokenCount: Int
    /// Longest contiguous run of non-matching ops (substitutions/insertions/deletions).
    public let longestMismatchRun: Int

    /// Plan §5.3: ignore the edit entirely if >30% of tokens changed — a wholesale
    /// rewrite teaches nothing. A short contiguous fix (even a >30% ratio on tiny
    /// sentences, e.g. "vakya aaj bharat" → "vaakya bharat") is NOT a rewrite.
    public var isWholesaleRewrite: Bool {
        let changed = substitutionCount + insertionCount + deletionCount
        let denominator = max(asrTokenCount, editedTokenCount)
        guard denominator > 0 else { return false }
        return Double(changed) / Double(denominator) > 0.3 && longestMismatchRun > 3
    }

    public init(candidates: [DiffCandidate], substitutionCount: Int, insertionCount: Int,
                deletionCount: Int, asrTokenCount: Int, editedTokenCount: Int,
                longestMismatchRun: Int) {
        self.candidates = candidates
        self.substitutionCount = substitutionCount
        self.insertionCount = insertionCount
        self.deletionCount = deletionCount
        self.asrTokenCount = asrTokenCount
        self.editedTokenCount = editedTokenCount
        self.longestMismatchRun = longestMismatchRun
    }
}

/// Word-aligned diff (Wagner–Fischer over tokens) between ASR/injected text and
/// user-edited text → candidate `(match, replacement)` pairs (plan §5.3).
///
/// Rules:
/// - Only substitution spans ≤3 tokens produce rules.
/// - A span of 1 token that differs only in case → `exact_cs`; otherwise `exact_ci`.
/// - A span of 2–3 tokens → `phrase` rule.
/// - Pure insertions/deletions are counted (for the `corrections` row) but produce no rules.
/// - If >30% of tokens changed (`isWholesaleRewrite`), no candidates at all.
public enum DiffLearner {
    public static func diff(asrText: String, editedText: String) -> DiffResult {
        let asrTokens = tokenize(asrText)
        let editedTokens = tokenize(editedText)
        let ops = alignment(asrTokens, editedTokens)

        var candidates: [DiffCandidate] = []
        var substitutionCount = 0
        var insertionCount = 0
        var deletionCount = 0

        var spanAsr: [String] = []
        var spanEdited: [String] = []
        var currentRun = 0
        var longestRun = 0

        func flushSpan() {
            defer { spanAsr = []; spanEdited = [] }
            guard !spanAsr.isEmpty, spanAsr.count == spanEdited.count, spanAsr.count <= 3 else { return }
            if spanAsr.count == 1 {
                let asr = spanAsr[0], edited = spanEdited[0]
                if asr.lowercased() == edited.lowercased() {
                    candidates.append(DiffCandidate(match: asr, replacement: edited,
                                                    matchKind: .exactCS, spanTokens: 1))
                } else {
                    candidates.append(DiffCandidate(match: asr, replacement: edited,
                                                    matchKind: .exactCI, spanTokens: 1))
                }
            } else {
                candidates.append(DiffCandidate(match: spanAsr.joined(separator: " "),
                                                replacement: spanEdited.joined(separator: " "),
                                                matchKind: .phrase,
                                                spanTokens: spanAsr.count))
            }
        }

        for op in ops {
            switch op {
            case .match(_, _):
                flushSpan()
                currentRun = 0
            case let .substitute(asr, edited):
                substitutionCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                spanAsr.append(asr)
                spanEdited.append(edited)
            case let .insert(insertedToken):
                insertionCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                _ = insertedToken
                flushSpan()
            case let .delete(deletedToken):
                deletionCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                _ = deletedToken
                flushSpan()
            }
        }
        flushSpan()

        return DiffResult(candidates: candidates,
                          substitutionCount: substitutionCount,
                          insertionCount: insertionCount,
                          deletionCount: deletionCount,
                          asrTokenCount: asrTokens.count,
                          editedTokenCount: editedTokens.count,
                          longestMismatchRun: longestRun)
    }

    // MARK: - internals

    private enum Op: Equatable {
        case match(String, String)
        case substitute(String, String)
        case insert(String)
        case delete(String)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).compactMap { surface in
            var core = ""
            for character in surface {
                if character.isLetter || character.isNumber {
                    core.append(character)
                } else if !core.isEmpty {
                    break
                }
            }
            return core.isEmpty ? nil : core
        }
    }

    /// Standard Wagner–Fischer alignment; returns ops from first token to last.
    private static func alignment(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        // dp[i][j] = edit distance between a[..<i] and b[..<j]
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in dp.indices { dp[i][0] = i }
        for j in dp[0].indices { dp[0][j] = j }
        // Half-open ranges are empty when either token list is empty. Closed
        // ranges such as `1...0` trap before the alignment can return the
        // corresponding all-insert/all-delete path.
        for i in 1..<dp.count {
            for j in 1..<dp[i].count {
                // Case-sensitive equality: a case-only difference is a substitution
                // (it must become an `exact_cs` candidate, plan §5.3), not a match.
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(dp[i - 1][j] + 1,        // delete
                               dp[i][j - 1] + 1,        // insert
                               dp[i - 1][j - 1] + cost) // substitute/match
            }
        }
        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1],
               a[i - 1] == b[j - 1] {
                ops.append(.match(a[i - 1], b[j - 1]))
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                ops.append(.substitute(a[i - 1], b[j - 1]))
                i -= 1; j -= 1
            } else if j > 0, dp[i][j] == dp[i][j - 1] + 1 {
                ops.append(.insert(b[j - 1]))
                j -= 1
            } else {
                ops.append(.delete(a[i - 1]))
                i -= 1
            }
        }
        return ops.reversed()
    }
}
