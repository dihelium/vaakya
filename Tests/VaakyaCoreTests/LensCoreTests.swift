import Foundation
import Testing
@testable import VaakyaCore

@Suite struct LensCoreTests {
    @Test func chatMessageJSONUsesLowercaseKeys() throws {
        let msg = LensChatMessage(role: "system", content: "hello")
        let data = try JSONEncoder().encode(msg)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["role"] as? String == "system")
        #expect(obj?["content"] as? String == "hello")
        #expect(obj?["Role"] == nil)
    }

    @Test func promptBuilderIncludesSectionsAndExcludesEmptyLLM() throws {
        let lens = LensSpec(id: "L1", title: "Decisions", requiresLLM: true,
                            body: "Do decisions.", systemTrust: "Trust rules.")
        let input = LensPromptInput(notesMarkdown: "Ship Friday",
                                    transcriptMarkdown: "Speaker 1: hello",
                                    contextMarkdown: "Product: X")
        let messages = LensPromptBuilder.buildMessages(lens: lens, input: input)
        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content.contains("Trust rules."))
        #expect(messages[0].content.contains("Do decisions."))
        #expect(messages[1].content.contains("[NOTES]"))
        #expect(messages[1].content.contains("Ship Friday"))
        #expect(messages[1].content.contains("[TRANSCRIPT]"))
        #expect(messages[1].content.contains("Speaker 1: hello"))
        #expect(messages[1].content.contains("[CONTEXT]"))
        #expect(messages[1].content.contains("Product: X"))
        #expect(!messages[1].content.contains("secret.wav"))
    }

    @Test func l0ReturnsNoMessages() {
        let lens = LensSpec(id: "L0", title: "Raw", requiresLLM: false, body: "copy")
        let messages = LensPromptBuilder.buildMessages(
            lens: lens,
            input: LensPromptInput(transcriptMarkdown: "hi"))
        #expect(messages.isEmpty)
    }

    @Test func catalogLoadsBundledLenses() throws {
        let specs = try LensCatalog.allSpecs()
        let ids = Set(specs.map(\.id))
        #expect(ids.contains("L0_raw_transcript"))
        #expect(ids.contains("L5_technical_interview"))
        #expect(ids.contains("L5b_interview_self_debrief"))
        let l5 = try LensCatalog.loadSpec(id: "L5_technical_interview")
        #expect(l5.requiresLLM)
        #expect(!l5.systemTrust.isEmpty)
        #expect(l5.body.contains("Technical interview notes"))
        #expect(l5.origin == .bundled)
        #expect(Set(LensCatalog.bundledIDs).isSubset(of: ids))
    }

    @Test func promoteStatusRewritesFrontMatter() throws {
        let md = """
        ---
        status: draft
        lens_id: L5
        model: test
        via: openai
        created_at: t0
        package_id: p
        fidelity: A1
        egress: B1
        input_sha256: abc
        ---

        # Body
        """
        let promoted = try LensFrontMatter.promoteStatus(in: md, to: "reviewed")
        #expect(promoted.contains("status: reviewed"))
        #expect(promoted.contains("# Body"))
        #expect(!promoted.contains("status: draft"))
    }

    @Test func lensRunsPersist() throws {
        let db = try VaakyaDatabase()
        let job = TranscriptionJobRecord(
            id: "job-lens",
            sourceName: "a.m4a",
            managedAudioPath: "x",
            sourceSHA256: "s",
            fileSizeBytes: 1,
            durationSeconds: 1,
            status: "completed",
            createdAt: "t0",
            updatedAt: "t0")
        try db.insertTranscriptionJob(job)
        #expect(try db.nextLensVersion(jobID: "job-lens", lensID: "L5") == 1)
        let run = LensRunRecord(
            id: UUID().uuidString,
            jobID: "job-lens",
            lensID: "L5",
            version: 1,
            via: "openai",
            egress: "B1",
            model: "gpt-4o",
            markdownPath: "lenses/L5.v1.md",
            inputSHA256: "abc",
            createdAt: "t1",
            updatedAt: "t1")
        try db.insertLensRun(run)
        #expect(try db.nextLensVersion(jobID: "job-lens", lensID: "L5") == 2)
        let runs = try db.lensRuns(jobID: "job-lens")
        #expect(runs.count == 1)
        try db.updateLensRunStatus(id: run.id, status: "reviewed", updatedAt: "t2")
        #expect(try db.lensRun(id: run.id)?.status == "reviewed")
    }

    @Test func migrationsIncludeLensRuns() throws {
        let db = try VaakyaDatabase()
        let tables = try db.queue.read { d in
            try String.fetchAll(d, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name
                """)
        }
        #expect(tables.contains("lens_runs"))
    }
}
