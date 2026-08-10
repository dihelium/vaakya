import Testing
@testable import VaakyaCore

@Suite struct DatabaseTests {
    private func makeDB() throws -> VaakyaDatabase {
        try VaakyaDatabase() // in-memory
    }

    @Test func migrationsCreateAllTables() throws {
        let db = try makeDB()
        let tables = try db.queue.read { d in
            try String.fetchAll(d, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name
                """)
        }
        for expected in ["dictations", "dictionary_entries", "replacement_rules", "corrections",
                         "transcription_jobs", "transcript_speakers", "transcript_turns", "lens_runs",
                         "ask_conversations", "ask_messages"] {
            #expect(tables.contains(expected), "missing table \(expected); got \(tables)")
        }
    }

    @Test func askConversationCascadeAndSeq() throws {
        let db = try makeDB()
        let now = "2026-08-09T00:00:00Z"
        try db.insertAskConversation(AskConversationRecord(
            id: "c1", title: "hello", scopeJSON: "{}", createdAt: now, updatedAt: now))
        try db.insertAskMessage(AskMessageRecord(
            id: "m1", conversationID: "c1", role: "user", content: "hi",
            createdAt: now, seq: 1))
        try db.insertAskMessage(AskMessageRecord(
            id: "m2", conversationID: "c1", role: "assistant", content: "yo",
            status: "complete", createdAt: now, seq: 2))
        #expect(try db.askMessages(conversationID: "c1").count == 2)
        #expect(try db.nextAskMessageSeq(conversationID: "c1") == 3)
        try db.deleteAskConversation(id: "c1")
        #expect(try db.askMessages(conversationID: "c1").isEmpty)
    }

    @Test func importedJobStateAndRecoveryAreDurable() throws {
        let db = try makeDB()
        let job = TranscriptionJobRecord(
            id: "job-1",
            sourceName: "interview.m4a",
            managedAudioPath: "TranscriptionJobs/job-1/source.m4a",
            sourceSHA256: "abc",
            fileSizeBytes: 123,
            durationSeconds: 12.5,
            createdAt: "t0",
            updatedAt: "t0")
        try db.insertTranscriptionJob(job)
        try db.updateTranscriptionJobState(
            id: "job-1",
            status: "running",
            activeStage: "diarizing",
            completedStage: "asr",
            progress: 0.4,
            updatedAt: "t1")

        #expect(try db.transcriptionJob(id: "job-1")?.status == "running")
        #expect(try db.recoverInterruptedTranscriptionJobs(updatedAt: "t2") == 1)
        let recovered = try #require(try db.transcriptionJob(id: "job-1"))
        #expect(recovered.status == "queued")
        #expect(recovered.activeStage == "diarizing")
        #expect(recovered.completedStage == "asr")
        #expect(recovered.progress == 0.4)
    }

    @Test func replacingTranscriptIsIdempotentAndDeleteCascades() throws {
        let db = try makeDB()
        let job = TranscriptionJobRecord(
            id: "job-2",
            sourceName: "interview.wav",
            managedAudioPath: "TranscriptionJobs/job-2/source.wav",
            sourceSHA256: "def",
            fileSizeBytes: 456,
            durationSeconds: 3,
            createdAt: "t0",
            updatedAt: "t0")
        try db.insertTranscriptionJob(job)
        let speakers = [TranscriptSpeakerRecord(jobID: "job-2", speakerKey: "S1",
                                                 displayName: "Interviewer", sortOrder: 0)]
        let turns = [TranscriptTurn(ordinal: 0, speakerKey: "S1", startSeconds: 0,
                                    endSeconds: 1, rawText: "Hello", finalText: "Hello")]

        try db.replaceTranscript(jobID: "job-2", speakers: speakers, turns: turns)
        try db.replaceTranscript(jobID: "job-2", speakers: speakers, turns: turns)
        #expect(try db.transcriptSpeakers(jobID: "job-2").count == 1)
        #expect(try db.transcriptTurns(jobID: "job-2").count == 1)
        #expect(try db.transcriptTurns(jobID: "job-2")[0].asTurn == turns[0])

        try db.deleteTranscriptionJob(id: "job-2")
        #expect(try db.transcriptionJob(id: "job-2") == nil)
        #expect(try db.transcriptSpeakers(jobID: "job-2").isEmpty)
        #expect(try db.transcriptTurns(jobID: "job-2").isEmpty)
    }

    @Test func insertAndFetchDictation() throws {
        let db = try makeDB()
        let id = try db.insertDictation(timestamp: "2026-08-02T10:00:00Z",
                                        rawText: "call vakya", finalText: "call vaakya",
                                        appContext: "com.apple.Notes")
        let fetched = try db.dictations()
        #expect(fetched.count == 1)
        #expect(fetched[0].id == id)
        #expect(fetched[0].rawText == "call vakya")
        #expect(fetched[0].finalText == "call vaakya")
        #expect(fetched[0].wordCount == 2)
        #expect(fetched[0].appContext == "com.apple.Notes")
    }

    @Test func updateDictationFinalText() throws {
        let db = try makeDB()
        let id = try db.insertDictation(timestamp: "t", rawText: "raw", finalText: "raw")
        try db.updateDictationFinalText(id: id, finalText: "corrected text here")
        let row = try db.dictations()[0]
        #expect(row.finalText == "corrected text here")
        #expect(row.wordCount == 3)
    }

    @Test func upsertRuleIncrementsOccurrences() throws {
        let db = try makeDB()
        let rule = ReplacementRule(match: "vakya", replacement: "vaakya")
        try db.upsertReplacementRule(rule, source: "manual", status: "active")
        try db.upsertReplacementRule(rule, source: "learned_explicit", status: "active")
        let rows = try db.rules()
        #expect(rows.count == 1) // unique (match, match_kind)
        #expect(rows[0].occurrences == 2)
    }

    @Test func rulesStatusFilteringAndStatusUpdate() throws {
        let db = try makeDB()
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "vaakya"),
                                     source: "learned_explicit", status: "active")
        try db.upsertReplacementRule(ReplacementRule(match: "hun", replacement: "hoon"),
                                     source: "learned_passive", status: "suggested")

        #expect(try db.activeRules().count == 1)
        #expect(try db.pendingSuggestionCount() == 1)

        let suggested = try db.rules(status: "suggested")
        #expect(suggested.count == 1)
        try db.setRuleStatus(id: suggested[0].id!, status: "active")
        #expect(try db.activeRules().count == 2)
        #expect(try db.pendingSuggestionCount() == 0)
    }

    @Test func upsertRevivesDisabledRuleToSuggested() throws {
        // Review fix: re-observed evidence on a disabled rule → suggested again.
        let db = try makeDB()
        let rule = ReplacementRule(match: "vakya", replacement: "vaakya")
        try db.upsertReplacementRule(rule, source: "manual", status: "active")
        let row = try db.rules()[0]
        try db.setRuleStatus(id: row.id!, status: "disabled")
        #expect(try db.rules()[0].status == "disabled")

        try db.upsertReplacementRule(rule, source: "learned_passive", status: "suggested")
        let revived = try db.rules()[0]
        #expect(revived.status == "suggested")
        #expect(revived.occurrences == 2)
        // Replacement is never silently overwritten.
        #expect(revived.replacement == "vaakya")
    }

    @Test func conflictingReplacementsAreBothStoredAsSuggested() throws {
        let db = try makeDB()
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "vaakya"),
                                     source: "learned_explicit", status: "active")
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "shrotha"),
                                     source: "learned_explicit", status: "active")

        let rows = try db.rules()
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.replacement)) == ["vaakya", "shrotha"])
        #expect(rows.allSatisfy { $0.status == "suggested" })
    }

    @Test func repeatedConflictEvidenceIncrementsOnlyItsAlternative() throws {
        let db = try makeDB()
        let first = ReplacementRule(match: "vakya", replacement: "vaakya")
        let second = ReplacementRule(match: "vakya", replacement: "shrotha")
        try db.upsertReplacementRule(first, source: "learned_passive")
        try db.upsertReplacementRule(second, source: "learned_passive")
        try db.upsertReplacementRule(second, source: "learned_passive")

        let byReplacement = Dictionary(uniqueKeysWithValues: try db.rules().map { ($0.replacement, $0) })
        #expect(byReplacement["vaakya"]?.occurrences == 1)
        #expect(byReplacement["shrotha"]?.occurrences == 2)
    }

    @Test func approvingOneConflictDisablesTheAlternatives() throws {
        let db = try makeDB()
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "vaakya"),
                                     source: "learned_passive")
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "shrotha"),
                                     source: "learned_passive")
        let chosen = try #require(db.rules().first { $0.replacement == "vaakya" })
        try db.setRuleStatus(id: try #require(chosen.id), status: "active")

        let byReplacement = Dictionary(uniqueKeysWithValues: try db.rules().map { ($0.replacement, $0) })
        #expect(byReplacement["vaakya"]?.status == "active")
        #expect(byReplacement["shrotha"]?.status == "disabled")
        #expect(try db.activeRules().count == 1)
    }

    @Test func evidenceForResolvedChoiceDoesNotReopenConflict() throws {
        let db = try makeDB()
        let chosenRule = ReplacementRule(match: "vakya", replacement: "vaakya")
        try db.upsertReplacementRule(chosenRule, source: "learned_passive")
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "shrotha"),
                                     source: "learned_passive")
        let chosen = try #require(db.rules().first { $0.replacement == "vaakya" })
        try db.setRuleStatus(id: try #require(chosen.id), status: "active")

        try db.upsertReplacementRule(chosenRule, source: "learned_passive")

        let byReplacement = Dictionary(uniqueKeysWithValues: try db.rules().map { ($0.replacement, $0) })
        #expect(byReplacement["vaakya"]?.status == "active")
        #expect(byReplacement["vaakya"]?.occurrences == 2)
        #expect(byReplacement["shrotha"]?.status == "disabled")
        #expect(try db.conflictingRuleIDs().isEmpty)
    }

    @Test func v1RuleTableMigratesWithoutLosingRows() throws {
        let db = try makeDB()
        try db.queue.write { sqlDB in
            try sqlDB.execute(sql: """
                DROP TABLE replacement_rules;
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
                INSERT INTO replacement_rules(match, replacement, match_kind, source, status)
                VALUES ('vakya', 'vaakya', 'exact_ci', 'manual', 'active');
                DELETE FROM grdb_migrations WHERE identifier = 'v2-rule-conflicts';
                """)
        }

        try VaakyaDatabase.migrate(db.queue)

        let rows = try db.rules()
        #expect(rows.count == 1)
        #expect(rows[0].match == "vakya")
        #expect(rows[0].replacement == "vaakya")
        try db.upsertReplacementRule(ReplacementRule(match: "vakya", replacement: "shrotha"),
                                     source: "learned_passive")
        #expect(try db.rules().count == 2)
    }

    @Test func incrementRuleHits() throws {
        let db = try makeDB()
        try db.upsertReplacementRule(ReplacementRule(match: "x", replacement: "y"),
                                     source: "manual", status: "active")
        let row = try db.rules()[0]
        #expect(row.hits == 0)
        try db.incrementRuleHits(id: row.id!)
        #expect(try db.rules()[0].hits == 1)
    }

    @Test func dictionaryEntryUpsertMergesTimesSeen() throws {
        let db = try makeDB()
        try db.upsertDictionaryEntry(term: "Ananya", kind: "name", source: "seeded_corpus", timesSeen: 2)
        try db.upsertDictionaryEntry(term: "Ananya", kind: "name", source: "seeded_corpus", timesSeen: 3)
        let rows = try db.dictionaryEntries()
        #expect(rows.count == 1)
        #expect(rows[0].timesSeen == 5)
    }

    @Test func correctionInsertAndFetch() throws {
        let db = try makeDB()
        let dictId = try db.insertDictation(timestamp: "t", rawText: "a b", finalText: "a b")
        let corrId = try db.insertCorrection(dictationId: dictId, asrText: "a b",
                                             editedText: "a c", capture: "passive_ax")
        let rows = try db.corrections()
        #expect(rows.count == 1)
        #expect(rows[0].id == corrId)
        #expect(rows[0].capture == "passive_ax")
    }
}
