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

/// A durable imported-audio transcription job.
public struct TranscriptionJobRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "transcription_jobs"

    public var id: String
    public var sourceName: String
    public var managedAudioPath: String
    public var sourceSHA256: String
    public var fileSizeBytes: Int64
    public var durationSeconds: Double
    public var expectedSpeakerCount: Int?
    public var status: String
    public var activeStage: String
    public var completedStage: String
    public var progress: Double
    public var errorMessage: String?
    public var rawText: String?
    public var finalText: String?
    public var createdAt: String
    public var updatedAt: String
    /// FluidAudio / Parakeet model id used for this job. Always the shared spine.
    public var asrModel: String

    public init(id: String,
                sourceName: String,
                managedAudioPath: String,
                sourceSHA256: String,
                fileSizeBytes: Int64,
                durationSeconds: Double,
                expectedSpeakerCount: Int? = nil,
                status: String = "queued",
                activeStage: String = "idle",
                completedStage: String = "none",
                progress: Double = 0,
                errorMessage: String? = nil,
                rawText: String? = nil,
                finalText: String? = nil,
                createdAt: String,
                updatedAt: String,
                asrModel: String = SpeechRecognitionProfile.shared.id) {
        self.id = id
        self.sourceName = sourceName
        self.managedAudioPath = managedAudioPath
        self.sourceSHA256 = sourceSHA256
        self.fileSizeBytes = fileSizeBytes
        self.durationSeconds = durationSeconds
        self.expectedSpeakerCount = expectedSpeakerCount
        self.status = status
        self.activeStage = activeStage
        self.completedStage = completedStage
        self.progress = progress
        self.errorMessage = errorMessage
        self.rawText = rawText
        self.finalText = finalText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.asrModel = asrModel
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceName = "source_name"
        case managedAudioPath = "managed_audio_path"
        case sourceSHA256 = "source_sha256"
        case fileSizeBytes = "file_size_bytes"
        case durationSeconds = "duration_seconds"
        case expectedSpeakerCount = "expected_speaker_count"
        case status
        case activeStage = "active_stage"
        case completedStage = "completed_stage"
        case progress
        case errorMessage = "error_message"
        case rawText = "raw_text"
        case finalText = "final_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case asrModel = "asr_model"
    }
}

/// A file-local diarized speaker label.
public struct TranscriptSpeakerRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "transcript_speakers"

    public var jobID: String
    public var speakerKey: String
    public var displayName: String
    public var sortOrder: Int

    public init(jobID: String, speakerKey: String, displayName: String, sortOrder: Int) {
        self.jobID = jobID
        self.speakerKey = speakerKey
        self.displayName = displayName
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case speakerKey = "speaker_key"
        case displayName = "display_name"
        case sortOrder = "sort_order"
    }
}

/// A persisted speaker-attributed turn.
public struct TranscriptTurnRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "transcript_turns"

    public var id: Int64?
    public var jobID: String
    public var ordinal: Int
    public var speakerKey: String
    public var startSeconds: Double
    public var endSeconds: Double
    public var rawText: String
    public var finalText: String
    public var confidence: Float?

    public init(id: Int64? = nil,
                jobID: String,
                ordinal: Int,
                speakerKey: String,
                startSeconds: Double,
                endSeconds: Double,
                rawText: String,
                finalText: String,
                confidence: Float? = nil) {
        self.id = id
        self.jobID = jobID
        self.ordinal = ordinal
        self.speakerKey = speakerKey
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.rawText = rawText
        self.finalText = finalText
        self.confidence = confidence
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case ordinal
        case speakerKey = "speaker_key"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case rawText = "raw_text"
        case finalText = "final_text"
        case confidence
    }

    public var asTurn: TranscriptTurn {
        TranscriptTurn(ordinal: ordinal,
                       speakerKey: speakerKey,
                       startSeconds: startSeconds,
                       endSeconds: endSeconds,
                       rawText: rawText,
                       finalText: finalText,
                       confidence: confidence)
    }
}

/// A persisted lens draft/review document for one transcription job.
public struct LensRunRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "lens_runs"

    public var id: String
    public var jobID: String
    public var lensID: String
    public var version: Int
    public var status: String
    public var via: String
    public var egress: String
    public var model: String?
    public var markdownPath: String
    public var inputSHA256: String?
    public var createdAt: String
    public var updatedAt: String

    public init(id: String,
                jobID: String,
                lensID: String,
                version: Int,
                status: String = "draft",
                via: String,
                egress: String,
                model: String? = nil,
                markdownPath: String,
                inputSHA256: String? = nil,
                createdAt: String,
                updatedAt: String) {
        self.id = id
        self.jobID = jobID
        self.lensID = lensID
        self.version = version
        self.status = status
        self.via = via
        self.egress = egress
        self.model = model
        self.markdownPath = markdownPath
        self.inputSHA256 = inputSHA256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case lensID = "lens_id"
        case version, status, via, egress, model
        case markdownPath = "markdown_path"
        case inputSHA256 = "input_sha256"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Archive Ask conversation thread.
public struct AskConversationRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "ask_conversations"

    public var id: String
    public var title: String
    public var scopeJSON: String
    public var createdAt: String
    public var updatedAt: String

    public init(id: String, title: String = "", scopeJSON: String,
                createdAt: String, updatedAt: String) {
        self.id = id
        self.title = title
        self.scopeJSON = scopeJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title
        case scopeJSON = "scope_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One message in an Archive Ask conversation.
public struct AskMessageRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "ask_messages"

    public var id: String
    public var conversationID: String
    public var role: String
    public var content: String
    public var status: String
    public var errorText: String?
    public var scopeJSON: String?
    public var runner: String?
    public var model: String?
    public var egressTier: String?
    public var sourcesJSON: String?
    public var packHash: String?
    public var createdAt: String
    public var seq: Int

    public init(id: String,
                conversationID: String,
                role: String,
                content: String,
                status: String = "complete",
                errorText: String? = nil,
                scopeJSON: String? = nil,
                runner: String? = nil,
                model: String? = nil,
                egressTier: String? = nil,
                sourcesJSON: String? = nil,
                packHash: String? = nil,
                createdAt: String,
                seq: Int) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.status = status
        self.errorText = errorText
        self.scopeJSON = scopeJSON
        self.runner = runner
        self.model = model
        self.egressTier = egressTier
        self.sourcesJSON = sourcesJSON
        self.packHash = packHash
        self.createdAt = createdAt
        self.seq = seq
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, status, runner, model, seq
        case conversationID = "conversation_id"
        case errorText = "error_text"
        case scopeJSON = "scope_json"
        case egressTier = "egress_tier"
        case sourcesJSON = "sources_json"
        case packHash = "pack_hash"
        case createdAt = "created_at"
    }
}
