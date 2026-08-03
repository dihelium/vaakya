import Foundation
import VaakyaCore

/// Runs the personalization pipeline between ASR and injection (plan §5, task 2.2):
/// Stage 1 deterministic replacement rules (always) → Stage 2 optional LLM cleanup.
/// Stores the raw/final evidence pair in the database for learning + eval.
final class PersonalizationPipeline: Sendable {
    private let db: VaakyaDatabase
    private let stage2Enabled: @Sendable () -> Bool

    init(db: VaakyaDatabase, stage2Enabled: @escaping @Sendable () -> Bool = { true }) {
        self.db = db
        self.stage2Enabled = stage2Enabled
    }

    struct Result: Equatable, Sendable {
        let text: String
        let llmCleaned: Bool
        let dictationId: Int64?
    }

    func process(rawText: String,
                 cleanupModel: CleanupModel?,
                 appContext: String? = nil,
                 timestamp: String = ISO8601DateFormatter().string(from: Date()),
                 duration: Double? = nil) async throws -> Result {
        // Stage 1 — deterministic rules from the dictionary.
        let rules = try db.activeRules()
        let stage1 = ReplacementEngine.apply(rawText, rules: rules)

        // Stage 2 — optional on-device LLM cleanup (guarded inside LLMCleanup).
        var final = stage1
        var llmCleaned = false
        if stage2Enabled(), let cleanupModel {
            let terms = try db.dictionaryEntries(status: "active").map(\.term)
            let outcome = await LLMCleanup.apply(input: stage1,
                                                 model: cleanupModel,
                                                 vocabulary: terms)
            final = outcome.text
            llmCleaned = outcome.accepted
        }

        // Persist the evidence pair (raw = post-ASR, final = what gets injected).
        let dictationId = try db.insertDictation(timestamp: timestamp,
                                                 durationSeconds: duration,
                                                 rawText: rawText,
                                                 finalText: final,
                                                 appContext: appContext,
                                                 llmCleaned: llmCleaned)
        return Result(text: final, llmCleaned: llmCleaned, dictationId: dictationId)
    }
}
