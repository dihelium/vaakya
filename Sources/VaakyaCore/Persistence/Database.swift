import Foundation
import GRDB

/// Wraps the GRDB database (`~/Library/Application Support/Vaakya/vaakya.db`,
/// WAL mode) and owns the schema migrations (plan §4).
public final class VaakyaDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue

    /// Open (or create) the database at `path` and migrate to the latest schema.
    public init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try Self.migrate(queue)
    }

    /// In-memory database for tests.
    public init() throws {
        queue = try DatabaseQueue()
        try Self.migrate(queue)
    }

    // MARK: - schema

    public static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE dictations(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  timestamp TEXT NOT NULL,
                  duration_seconds REAL,
                  raw_text TEXT,
                  final_text TEXT,
                  app_context TEXT,
                  word_count INTEGER NOT NULL DEFAULT 0,
                  llm_cleaned INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT DEFAULT (datetime('now'))
                );
                CREATE TABLE dictionary_entries(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  term TEXT NOT NULL UNIQUE,
                  kind TEXT NOT NULL DEFAULT 'word',
                  source TEXT NOT NULL,
                  status TEXT NOT NULL DEFAULT 'active',
                  times_seen INTEGER NOT NULL DEFAULT 1,
                  created_at TEXT DEFAULT (datetime('now')),
                  updated_at TEXT
                );
                CREATE TABLE replacement_rules(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  match TEXT NOT NULL,
                  replacement TEXT NOT NULL,
                  match_kind TEXT NOT NULL DEFAULT 'exact_ci',
                  source TEXT NOT NULL,
                  status TEXT NOT NULL DEFAULT 'suggested',
                  occurrences INTEGER NOT NULL DEFAULT 1,
                  hits INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT DEFAULT (datetime('now')),
                  updated_at TEXT,
                  UNIQUE(match, match_kind)
                );
                CREATE TABLE corrections(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  dictation_id INTEGER REFERENCES dictations(id),
                  asr_text TEXT,
                  edited_text TEXT,
                  capture TEXT NOT NULL,
                  app_context TEXT,
                  created_at TEXT DEFAULT (datetime('now'))
                );
                """)
        }
        migrator.registerMigration("v2-rule-conflicts") { db in
            try db.execute(sql: """
                CREATE TABLE replacement_rules_v2(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  match TEXT NOT NULL,
                  replacement TEXT NOT NULL,
                  match_kind TEXT NOT NULL DEFAULT 'exact_ci',
                  source TEXT NOT NULL,
                  status TEXT NOT NULL DEFAULT 'suggested',
                  occurrences INTEGER NOT NULL DEFAULT 1,
                  hits INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT DEFAULT (datetime('now')),
                  updated_at TEXT,
                  UNIQUE(match, match_kind, replacement)
                );
                INSERT INTO replacement_rules_v2(
                  id, match, replacement, match_kind, source, status,
                  occurrences, hits, created_at, updated_at
                )
                SELECT id, match, replacement, match_kind, source, status,
                       occurrences, hits, created_at, updated_at
                FROM replacement_rules;
                DROP TABLE replacement_rules;
                ALTER TABLE replacement_rules_v2 RENAME TO replacement_rules;
                """)
        }
        migrator.registerMigration("v3-imported-transcripts") { db in
            try db.execute(sql: """
                CREATE TABLE transcription_jobs(
                  id TEXT PRIMARY KEY,
                  source_name TEXT NOT NULL,
                  managed_audio_path TEXT NOT NULL,
                  source_sha256 TEXT NOT NULL,
                  file_size_bytes INTEGER NOT NULL,
                  duration_seconds REAL NOT NULL,
                  expected_speaker_count INTEGER,
                  status TEXT NOT NULL,
                  active_stage TEXT NOT NULL,
                  completed_stage TEXT NOT NULL,
                  progress REAL NOT NULL DEFAULT 0,
                  error_message TEXT,
                  raw_text TEXT,
                  final_text TEXT,
                  created_at TEXT NOT NULL DEFAULT (datetime('now')),
                  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                );
                CREATE TABLE transcript_speakers(
                  job_id TEXT NOT NULL REFERENCES transcription_jobs(id) ON DELETE CASCADE,
                  speaker_key TEXT NOT NULL,
                  display_name TEXT NOT NULL,
                  sort_order INTEGER NOT NULL,
                  PRIMARY KEY(job_id, speaker_key)
                );
                CREATE TABLE transcript_turns(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  job_id TEXT NOT NULL REFERENCES transcription_jobs(id) ON DELETE CASCADE,
                  ordinal INTEGER NOT NULL,
                  speaker_key TEXT NOT NULL,
                  start_seconds REAL NOT NULL,
                  end_seconds REAL NOT NULL,
                  raw_text TEXT NOT NULL,
                  final_text TEXT NOT NULL,
                  confidence REAL,
                  UNIQUE(job_id, ordinal),
                  FOREIGN KEY(job_id, speaker_key)
                    REFERENCES transcript_speakers(job_id, speaker_key) ON DELETE CASCADE
                );
                """)
        }
        migrator.registerMigration("v4-lens-runs") { db in
            try db.execute(sql: """
                CREATE TABLE lens_runs(
                  id TEXT PRIMARY KEY,
                  job_id TEXT NOT NULL REFERENCES transcription_jobs(id) ON DELETE CASCADE,
                  lens_id TEXT NOT NULL,
                  version INTEGER NOT NULL,
                  status TEXT NOT NULL,
                  via TEXT NOT NULL,
                  egress TEXT NOT NULL,
                  model TEXT,
                  markdown_path TEXT NOT NULL,
                  input_sha256 TEXT,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL,
                  UNIQUE(job_id, lens_id, version)
                );
                CREATE INDEX lens_runs_job_id ON lens_runs(job_id);
                """)
        }
        migrator.registerMigration("v5-archive-ask") { db in
            try db.execute(sql: """
                CREATE TABLE ask_conversations(
                  id TEXT PRIMARY KEY,
                  title TEXT NOT NULL DEFAULT '',
                  scope_json TEXT NOT NULL DEFAULT '{"mode":"wholeArchive","jobIDs":[]}',
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
                CREATE TABLE ask_messages(
                  id TEXT PRIMARY KEY,
                  conversation_id TEXT NOT NULL REFERENCES ask_conversations(id) ON DELETE CASCADE,
                  role TEXT NOT NULL,
                  content TEXT NOT NULL,
                  status TEXT NOT NULL DEFAULT 'complete',
                  error_text TEXT,
                  scope_json TEXT,
                  runner TEXT,
                  model TEXT,
                  egress_tier TEXT,
                  sources_json TEXT,
                  pack_hash TEXT,
                  created_at TEXT NOT NULL,
                  seq INTEGER NOT NULL,
                  UNIQUE(conversation_id, seq)
                );
                CREATE INDEX ask_messages_conv_seq ON ask_messages(conversation_id, seq);
                """)
        }
        migrator.registerMigration("v6-shared-asr-model") { db in
            try db.execute(sql: """
                ALTER TABLE transcription_jobs
                ADD COLUMN asr_model TEXT NOT NULL DEFAULT 'parakeet-tdt-0.6b-v2';
                """)
        }
        try migrator.migrate(queue)
    }

    // MARK: - dictations

    @discardableResult
    public func insertDictation(timestamp: String, durationSeconds: Double? = nil,
                                rawText: String? = nil, finalText: String? = nil,
                                appContext: String? = nil, llmCleaned: Bool = false) throws -> Int64 {
        let wordCount = (finalText ?? rawText ?? "")
            .split(whereSeparator: \.isWhitespace).count
        var record = DictationRecord(timestamp: timestamp,
                                     durationSeconds: durationSeconds,
                                     rawText: rawText,
                                     finalText: finalText,
                                     appContext: appContext,
                                     wordCount: wordCount,
                                     llmCleaned: llmCleaned)
        try queue.write { db in
            try record.insert(db)
        }
        return record.id ?? -1
    }

    public func dictations(limit: Int = 100) throws -> [DictationRecord] {
        try queue.read { db in
            try DictationRecord.order(Column("id").desc).limit(limit).fetchAll(db)
        }
    }

    /// Update a dictation's final text (History panel edit, plan §5.5).
    public func updateDictationFinalText(id: Int64, finalText: String) throws {
        let wordCount = finalText.split(whereSeparator: \.isWhitespace).count
        try queue.write { db in
            try db.execute(sql: """
                UPDATE dictations SET final_text = ?, word_count = ?
                WHERE id = ?
                """, arguments: [finalText, wordCount, id])
        }
    }

    // MARK: - replacement rules

    /// Insert a rule, or bump the matching alternative's evidence count.
    /// Different replacements for one match are all retained as suggested so
    /// the owner can resolve the conflict without losing evidence.
    public func upsertReplacementRule(_ rule: ReplacementRule, source: String,
                                      status: String = "suggested") throws {
        try queue.write { db in
            let alternativeStatuses = try String.fetchAll(db, sql: """
                SELECT status FROM replacement_rules
                WHERE match = ? AND match_kind = ? AND replacement != ?
                """, arguments: [rule.match, rule.matchKind.rawValue, rule.replacement])
            let existingStatus = try String.fetchOne(db, sql: """
                SELECT status FROM replacement_rules
                WHERE match = ? AND match_kind = ? AND replacement = ?
                """, arguments: [rule.match, rule.matchKind.rawValue, rule.replacement])
            let hasConflict = alternativeStatuses.contains("suggested")
                || (!alternativeStatuses.isEmpty && (existingStatus == nil || existingStatus == "disabled"))
            if hasConflict {
                try db.execute(sql: """
                    UPDATE replacement_rules
                    SET status = 'suggested', updated_at = datetime('now')
                    WHERE match = ? AND match_kind = ?
                    """, arguments: [rule.match, rule.matchKind.rawValue])
            }
            let effectiveStatus = hasConflict ? "suggested" : status
            try db.execute(sql: """
                INSERT INTO replacement_rules(match, replacement, match_kind, source, status, occurrences)
                VALUES (?, ?, ?, ?, ?, 1)
                ON CONFLICT(match, match_kind, replacement) DO UPDATE SET
                  occurrences = occurrences + 1,
                  status = CASE
                    WHEN excluded.status = 'active' THEN 'active'
                    WHEN replacement_rules.status = 'disabled' THEN 'suggested'
                    ELSE replacement_rules.status
                  END,
                  updated_at = datetime('now')
                """, arguments: [rule.match, rule.replacement, rule.matchKind.rawValue, source, effectiveStatus])
        }
    }

    public func rules(status: String? = nil) throws -> [ReplacementRuleRecord] {
        try queue.read { db in
            var request = ReplacementRuleRecord.all()
            if let status {
                request = request.filter(Column("status") == status)
            }
            return try request.fetchAll(db)
        }
    }

    public func activeRules() throws -> [ReplacementRule] {
        try rules(status: "active").map(\.asRule)
    }

    public func pendingSuggestionCount() throws -> Int {
        try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM replacement_rules WHERE status = 'suggested'
                """) ?? 0
        }
    }

    /// IDs participating in an unresolved replacement conflict.
    public func conflictingRuleIDs() throws -> Set<Int64> {
        try queue.read { db in
            let ids = try Int64.fetchAll(db, sql: """
                SELECT DISTINCT a.id
                FROM replacement_rules a
                JOIN replacement_rules b
                  ON a.match = b.match
                 AND a.match_kind = b.match_kind
                 AND a.replacement != b.replacement
                WHERE a.status = 'suggested' AND b.status = 'suggested'
                """)
            return Set(ids)
        }
    }

    public func setRuleStatus(id: Int64, status: String) throws {
        try queue.write { db in
            if status == "active",
               let selected = try ReplacementRuleRecord
                .filter(Column("id") == id)
                .fetchOne(db) {
                try db.execute(sql: """
                    UPDATE replacement_rules
                    SET status = 'disabled', updated_at = datetime('now')
                    WHERE match = ? AND match_kind = ? AND id != ?
                    """, arguments: [selected.match, selected.matchKind, id])
            }
            try db.execute(sql: """
                UPDATE replacement_rules SET status = ?, updated_at = datetime('now') WHERE id = ?
                """, arguments: [status, id])
        }
    }

    /// Called when a rule's replacement is actually applied by the engine.
    public func incrementRuleHits(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE replacement_rules SET hits = hits + 1 WHERE id = ?
                """, arguments: [id])
        }
    }

    // MARK: - dictionary entries

    public func upsertDictionaryEntry(term: String, kind: String, source: String,
                                      status: String = "suggested", timesSeen: Int = 1) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO dictionary_entries(term, kind, source, status, times_seen)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(term) DO UPDATE SET
                  times_seen = dictionary_entries.times_seen + excluded.times_seen,
                  updated_at = datetime('now')
                """, arguments: [term, kind, source, status, timesSeen])
        }
    }

    public func dictionaryEntries(status: String? = nil) throws -> [DictionaryEntryRecord] {
        try queue.read { db in
            var request = DictionaryEntryRecord.all()
            if let status {
                request = request.filter(Column("status") == status)
            }
            return try request.fetchAll(db)
        }
    }

    public func setEntryStatus(id: Int64, status: String) throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE dictionary_entries SET status = ?, updated_at = datetime('now') WHERE id = ?
                """, arguments: [status, id])
        }
    }

    // MARK: - corrections

    @discardableResult
    public func insertCorrection(dictationId: Int64?, asrText: String?, editedText: String?,
                                 capture: String, appContext: String? = nil) throws -> Int64 {
        var record = CorrectionRecord(dictationId: dictationId, asrText: asrText,
                                      editedText: editedText, capture: capture,
                                      appContext: appContext)
        try queue.write { db in
            try record.insert(db)
        }
        return record.id ?? -1
    }

    public func corrections(limit: Int = 100) throws -> [CorrectionRecord] {
        try queue.read { db in
            try CorrectionRecord.order(Column("id").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - imported transcript jobs

    @discardableResult
    public func insertTranscriptionJob(_ job: TranscriptionJobRecord) throws -> String {
        var record = job
        try queue.write { db in
            try record.insert(db)
        }
        return record.id
    }

    public func transcriptionJobs(limit: Int = 100) throws -> [TranscriptionJobRecord] {
        try queue.read { db in
            try TranscriptionJobRecord
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func transcriptionJob(id: String) throws -> TranscriptionJobRecord? {
        try queue.read { db in
            try TranscriptionJobRecord.fetchOne(db, key: id)
        }
    }

    public func updateTranscriptionJobState(
        id: String,
        status: String,
        activeStage: String,
        completedStage: String,
        progress: Double,
        errorMessage: String? = nil,
        rawText: String? = nil,
        finalText: String? = nil,
        updatedAt: String
    ) throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE transcription_jobs
                SET status = ?, active_stage = ?, completed_stage = ?, progress = ?,
                    error_message = ?, raw_text = COALESCE(?, raw_text),
                    final_text = COALESCE(?, final_text), updated_at = ?
                WHERE id = ?
                """, arguments: [status, activeStage, completedStage, progress,
                                  errorMessage, rawText, finalText, updatedAt, id])
        }
    }

    public func recoverInterruptedTranscriptionJobs(updatedAt: String) throws -> Int {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE transcription_jobs
                SET status = 'queued', error_message = NULL, updated_at = ?
                WHERE status = 'running'
                """, arguments: [updatedAt])
            return db.changesCount
        }
    }

    public func replaceTranscript(
        jobID: String,
        speakers: [TranscriptSpeakerRecord],
        turns: [TranscriptTurn]
    ) throws {
        try queue.write { db in
            try TranscriptTurnRecord
                .filter(Column("job_id") == jobID)
                .deleteAll(db)
            try TranscriptSpeakerRecord
                .filter(Column("job_id") == jobID)
                .deleteAll(db)

            for speaker in speakers {
                var record = speaker
                try record.insert(db)
            }
            for turn in turns {
                var record = TranscriptTurnRecord(
                    jobID: jobID,
                    ordinal: turn.ordinal,
                    speakerKey: turn.speakerKey,
                    startSeconds: turn.startSeconds,
                    endSeconds: turn.endSeconds,
                    rawText: turn.rawText,
                    finalText: turn.finalText,
                    confidence: turn.confidence)
                try record.insert(db)
            }
        }
    }

    public func transcriptSpeakers(jobID: String) throws -> [TranscriptSpeakerRecord] {
        try queue.read { db in
            try TranscriptSpeakerRecord
                .filter(Column("job_id") == jobID)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    public func transcriptTurns(jobID: String) throws -> [TranscriptTurnRecord] {
        try queue.read { db in
            try TranscriptTurnRecord
                .filter(Column("job_id") == jobID)
                .order(Column("ordinal"))
                .fetchAll(db)
        }
    }

    public func deleteTranscriptionJob(id: String) throws {
        try _ = queue.write { db in
            try TranscriptionJobRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }

    public func updateTranscriptSpeakerDisplayName(
        jobID: String,
        speakerKey: String,
        displayName: String
    ) throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE transcript_speakers
                SET display_name = ?
                WHERE job_id = ? AND speaker_key = ?
                """, arguments: [displayName, jobID, speakerKey])
        }
    }

    // MARK: - lens runs

    public func nextLensVersion(jobID: String, lensID: String) throws -> Int {
        try queue.read { db in
            let max = try Int.fetchOne(db, sql: """
                SELECT MAX(version) FROM lens_runs
                WHERE job_id = ? AND lens_id = ?
                """, arguments: [jobID, lensID])
            return (max ?? 0) + 1
        }
    }

    @discardableResult
    public func insertLensRun(_ run: LensRunRecord) throws -> String {
        var record = run
        try queue.write { db in
            try record.insert(db)
        }
        return record.id
    }

    public func lensRuns(jobID: String) throws -> [LensRunRecord] {
        try queue.read { db in
            try LensRunRecord
                .filter(Column("job_id") == jobID)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    public func lensRun(id: String) throws -> LensRunRecord? {
        try queue.read { db in
            try LensRunRecord.fetchOne(db, key: id)
        }
    }

    public func updateLensRunStatus(id: String, status: String, updatedAt: String) throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE lens_runs SET status = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [status, updatedAt, id])
        }
    }

    // MARK: - archive ask

    public func insertAskConversation(_ conv: AskConversationRecord) throws {
        var record = conv
        try queue.write { db in
            try record.insert(db)
        }
    }

    public func updateAskConversation(_ conv: AskConversationRecord) throws {
        try queue.write { db in
            try conv.update(db)
        }
    }

    public func deleteAskConversation(id: String) throws {
        try _ = queue.write { db in
            try AskConversationRecord.filter(Column("id") == id).deleteAll(db)
        }
    }

    public func askConversations(limit: Int = 100) throws -> [AskConversationRecord] {
        try queue.read { db in
            try AskConversationRecord
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func askConversation(id: String) throws -> AskConversationRecord? {
        try queue.read { db in
            try AskConversationRecord.fetchOne(db, key: id)
        }
    }

    public func nextAskMessageSeq(conversationID: String) throws -> Int {
        try queue.read { db in
            let max = try Int.fetchOne(db, sql: """
                SELECT MAX(seq) FROM ask_messages WHERE conversation_id = ?
                """, arguments: [conversationID])
            return (max ?? 0) + 1
        }
    }

    public func insertAskMessage(_ message: AskMessageRecord) throws {
        var record = message
        try queue.write { db in
            try record.insert(db)
        }
    }

    /// Atomically allocate two sequence numbers and insert user + pending assistant.
    public func insertAskUserAndPendingAssistant(
        conversationID: String,
        user: AskMessageRecord,
        assistant: AskMessageRecord
    ) throws -> (user: AskMessageRecord, assistant: AskMessageRecord) {
        try queue.write { db -> (AskMessageRecord, AskMessageRecord) in
            let pending = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM ask_messages
                WHERE conversation_id = ? AND role = 'assistant' AND status = 'pending'
                """, arguments: [conversationID]) ?? 0
            if pending > 0 {
                throw NSError(
                    domain: "VaakyaAsk",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Conversation already has an in-flight Ask request."])
            }
            let maxSeq = try Int.fetchOne(db, sql: """
                SELECT MAX(seq) FROM ask_messages WHERE conversation_id = ?
                """, arguments: [conversationID]) ?? 0
            var u = user
            var a = assistant
            u.seq = maxSeq + 1
            a.seq = maxSeq + 2
            try u.insert(db)
            try a.insert(db)
            return (u, a)
        }
    }

    public func updateAskMessage(_ message: AskMessageRecord) throws {
        try queue.write { db in
            try message.update(db)
        }
    }

    public func askMessages(conversationID: String) throws -> [AskMessageRecord] {
        try queue.read { db in
            try AskMessageRecord
                .filter(Column("conversation_id") == conversationID)
                .order(Column("seq").asc)
                .fetchAll(db)
        }
    }

    public func hasPendingAskAssistant(conversationID: String) throws -> Bool {
        try queue.read { db in
            let n = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM ask_messages
                WHERE conversation_id = ? AND role = 'assistant' AND status = 'pending'
                """, arguments: [conversationID]) ?? 0
            return n > 0
        }
    }

    /// Mark abandoned pending assistant rows after restart.
    public func interruptPendingAskMessages(updatedContent: String = "Interrupted — send again.") throws -> Int {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE ask_messages
                SET status = 'interrupted', error_text = ?, content = CASE
                  WHEN content = '' OR content IS NULL THEN ? ELSE content END
                WHERE status = 'pending' AND role = 'assistant'
                """, arguments: [updatedContent, updatedContent])
            return db.changesCount
        }
    }

    public func interruptPendingAskMessages(conversationID: String,
                                            updatedContent: String = "Cancelled.") throws -> Int {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE ask_messages
                SET status = 'interrupted', error_text = ?, content = CASE
                  WHEN content = '' OR content IS NULL THEN ? ELSE content END
                WHERE conversation_id = ? AND status = 'pending' AND role = 'assistant'
                """, arguments: [updatedContent, updatedContent, conversationID])
            return db.changesCount
        }
    }

    public func completedTranscriptionJobs(limit: Int = 500) throws -> [TranscriptionJobRecord] {
        try queue.read { db in
            try TranscriptionJobRecord
                .filter(Column("status") == "completed")
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
