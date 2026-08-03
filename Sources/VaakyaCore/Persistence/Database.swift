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
}
