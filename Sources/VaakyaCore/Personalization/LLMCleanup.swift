import Foundation

/// Abstraction over an on-device language model used by Stage 2 (plan §5.2).
/// The app target's Foundation Models adapter (macOS 26) conforms to this;
/// tests inject stubs.
public protocol CleanupModel: Sendable {
    /// Complete the prompt, returning the raw text output.
    func complete(prompt: String) async throws -> String
}

/// Stage 2 — optional on-device LLM cleanup with hard guards (plan §5.2).
///
/// Guards (all enforced here, all testable):
/// - no model → passthrough (`modelUnavailable`)
/// - configurable timeout (default 1.5 s) → passthrough (`timeout`)
/// - output token-count ratio must stay within `[minTokenRatio, maxTokenRatio]` of the
///   input, and shared-token overlap must be ≥ `minSharedTokenOverlap`; otherwise
///   passthrough (`ratioOutOfRange` / `insufficientOverlap`)
/// - empty output → passthrough (`emptyOutput`)
///
/// The prompt instructs the model to only fix punctuation/casing using the
/// vocabulary as authoritative spellings — never translate or add content.
public enum LLMCleanup {
    public struct CleanupConfig: Sendable, Equatable {
        public var maxVocabularyTerms: Int
        public var timeout: Duration
        public var minTokenRatio: Double
        public var maxTokenRatio: Double
        public var minSharedTokenOverlap: Double

        public init(maxVocabularyTerms: Int = 100,
                    timeout: Duration = .milliseconds(1500),
                    minTokenRatio: Double = 0.5,
                    maxTokenRatio: Double = 2.0,
                    minSharedTokenOverlap: Double = 0.4) {
            self.maxVocabularyTerms = maxVocabularyTerms
            self.timeout = timeout
            self.minTokenRatio = minTokenRatio
            self.maxTokenRatio = maxTokenRatio
            self.minSharedTokenOverlap = minSharedTokenOverlap
        }
    }

    public enum FallbackReason: String, Sendable, Equatable {
        case modelUnavailable
        case timeout
        case threwError
        case emptyOutput
        case ratioOutOfRange
        case insufficientOverlap
    }

    public struct CleanupOutcome: Sendable, Equatable {
        /// The text to use (LLM output when accepted, input otherwise).
        public let text: String
        /// True when the LLM output passed every guard and was used.
        public let accepted: Bool
        /// Why we fell back (nil when accepted).
        public let reason: FallbackReason?

        init(text: String, accepted: Bool, reason: FallbackReason?) {
            self.text = text
            self.accepted = accepted
            self.reason = reason
        }
    }

    private enum CleanupError: Error {
        case timedOut
    }

    /// Build the system-style instruction + vocabulary block (deterministic, testable).
    ///
    /// Injection-hardening (security review): dictated text and vocabulary terms
    /// are user/import-controlled, so control characters and newlines are stripped
    /// before they can reach the instruction block as separators.
    public static func buildPrompt(text: String, vocabulary: [String], config: CleanupConfig = CleanupConfig()) -> String {
        let safeText = sanitize(text)
        let terms = vocabulary.prefix(config.maxVocabularyTerms).map(sanitize).filter { !$0.isEmpty }
        let vocabBlock = terms.isEmpty
            ? "No authoritative spellings provided."
            : terms.map { "- \($0)" }.joined(separator: "\n")
        return """
        You are a dictation post-processor. Fix punctuation and casing only.
        These spellings are authoritative and must be kept exactly as written:
        \(vocabBlock)
        Never translate, never change meaning, never add or remove content.
        Output only the corrected text, with no preamble or quotes.

        Text:
        \(safeText)
        """
    }

    /// Collapse whitespace/control characters so user-controlled content cannot
    /// smuggle instructions into the prompt.
    static func sanitize(_ s: String) -> String {
        let control = CharacterSet.controlCharacters
        let newlines = CharacterSet.newlines
        return s.unicodeScalars
            .filter { !control.contains($0) && !newlines.contains($0) && $0 != "\t" }
            .map(String.init)
            .joined()
    }

    /// Run Stage 2 with every guard enforced. Never throws; falls back to the input.
    public static func apply(input: String,
                             model: CleanupModel?,
                             vocabulary: [String],
                             config: CleanupConfig = CleanupConfig()) async -> CleanupOutcome {
        guard let model else {
            return CleanupOutcome(text: input, accepted: false, reason: .modelUnavailable)
        }
        let prompt = buildPrompt(text: input, vocabulary: vocabulary, config: config)

        let raw: String
        do {
            raw = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await model.complete(prompt: prompt) }
                group.addTask {
                    try await Task.sleep(for: config.timeout)
                    throw CleanupError.timedOut
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch is CleanupError {
            return CleanupOutcome(text: input, accepted: false, reason: .timeout)
        } catch {
            return CleanupOutcome(text: input, accepted: false, reason: .threwError)
        }

        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CleanupOutcome(text: input, accepted: false, reason: .emptyOutput)
        }

        let inTokens = tokenCount(input)
        let outTokens = tokenCount(raw)
        let ratio = Double(outTokens) / Double(max(inTokens, 1))
        guard ratio >= config.minTokenRatio, ratio <= config.maxTokenRatio else {
            return CleanupOutcome(text: input, accepted: false, reason: .ratioOutOfRange)
        }

        let overlap = sharedTokenOverlap(input, raw)
        guard overlap >= config.minSharedTokenOverlap else {
            return CleanupOutcome(text: input, accepted: false, reason: .insufficientOverlap)
        }

        return CleanupOutcome(text: raw, accepted: true, reason: nil)
    }

    // MARK: - token helpers (pure)

    public static func tokenCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// |A ∩ B| / max(|A|, |B|) over lowercased whitespace tokens.
    public static func sharedTokenOverlap(_ a: String, _ b: String) -> Double {
        func set(_ s: String) -> Set<String> {
            Set(s.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
        }
        let sa = set(a), sb = set(b)
        let denom = max(sa.count, sb.count)
        guard denom > 0 else { return 0 }
        return Double(sa.intersection(sb).count) / Double(denom)
    }
}
