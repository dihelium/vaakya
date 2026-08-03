import Foundation
import GRDB

/// `dictations` row (plan §4). Stores both `raw_text` (post-ASR) and
/// `final_text` (post-personalization, what was injected) — the evidence pair
/// for learning and for the eval harness.
public struct DictationRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "dictations"

    public var id: Int64?
    public var timestamp: String
    public var durationSeconds: Double?
    public var rawText: String?
    public var finalText: String?
    public var appContext: String?
    public var wordCount: Int
    public var llmCleaned: Bool
    public var createdAt: String?

    public init(id: Int64? = nil, timestamp: String, durationSeconds: Double? = nil,
                rawText: String? = nil, finalText: String? = nil, appContext: String? = nil,
                wordCount: Int = 0, llmCleaned: Bool = false, createdAt: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.rawText = rawText
        self.finalText = finalText
        self.appContext = appContext
        self.wordCount = wordCount
        self.llmCleaned = llmCleaned
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp
        case durationSeconds = "duration_seconds"
        case rawText = "raw_text"
        case finalText = "final_text"
        case appContext = "app_context"
        case wordCount = "word_count"
        case llmCleaned = "llm_cleaned"
        case createdAt = "created_at"
    }
}

/// `dictionary_entries` row — the vocabulary the app knows (plan §4).
public struct DictionaryEntryRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "dictionary_entries"

    public var id: Int64?
    public var term: String
    public var kind: String            // word | name | phrase
    public var source: String          // seeded_corpus | learned_passive | learned_explicit | manual
    public var status: String          // active | suggested | disabled
    public var timesSeen: Int
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: Int64? = nil, term: String, kind: String, source: String,
                status: String = "active", timesSeen: Int = 1,
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.term = term
        self.kind = kind
        self.source = source
        self.status = status
        self.timesSeen = timesSeen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    private enum CodingKeys: String, CodingKey {
        case id, term, kind, source, status
        case timesSeen = "times_seen"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `replacement_rules` row — misrecognition → correction (plan §4).
public struct ReplacementRuleRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "replacement_rules"

    public var id: Int64?
    public var match: String
    public var replacement: String
    public var matchKind: String       // exact_ci | exact_cs | phrase
    public var source: String
    public var status: String          // suggested | active | disabled
    public var occurrences: Int
    public var hits: Int
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: Int64? = nil, match: String, replacement: String, matchKind: String,
                source: String, status: String = "suggested", occurrences: Int = 1,
                hits: Int = 0, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.match = match
        self.replacement = replacement
        self.matchKind = matchKind
        self.source = source
        self.status = status
        self.occurrences = occurrences
        self.hits = hits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The pure rule this row represents.
    public var asRule: ReplacementRule {
        ReplacementRule(match: match, replacement: replacement,
                        matchKind: RuleMatchKind(rawValue: matchKind) ?? .exactCI)
    }

    private enum CodingKeys: String, CodingKey {
        case id, match, replacement, source, status, occurrences, hits
        case matchKind = "match_kind"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// `corrections` row — raw learning evidence (plan §4).
public struct CorrectionRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "corrections"

    public var id: Int64?
    public var dictationId: Int64?
    public var asrText: String?
    public var editedText: String?
    public var capture: String         // passive_ax | explicit_history
    public var appContext: String?
    public var createdAt: String?

    public init(id: Int64? = nil, dictationId: Int64? = nil, asrText: String? = nil,
                editedText: String? = nil, capture: String, appContext: String? = nil,
                createdAt: String? = nil) {
        self.id = id
        self.dictationId = dictationId
        self.asrText = asrText
        self.editedText = editedText
        self.capture = capture
        self.appContext = appContext
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    private enum CodingKeys: String, CodingKey {
        case id, capture
        case dictationId = "dictation_id"
        case asrText = "asr_text"
        case editedText = "edited_text"
        case appContext = "app_context"
        case createdAt = "created_at"
    }
}
