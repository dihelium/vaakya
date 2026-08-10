import Foundation
import Testing
@testable import VaakyaCore

@Suite struct ArchiveAskCoreTests {
    @Test func packerAssignsStableSourceIDsAndPrefersPinnedJobs() {
        let jobs = [
            ArchiveJobSummary(
                id: "a",
                displayTitle: "standup",
                createdAt: "2026-08-01T10:00:00Z",
                notes: "Ship ranking next week",
                turns: [
                    ArchiveTurn(startSeconds: 0, speaker: "A", text: "We should ship ranking after eval."),
                ]),
            ArchiveJobSummary(
                id: "b",
                displayTitle: "1:1",
                createdAt: "2026-08-07T10:00:00Z",
                notes: "",
                turns: [
                    ArchiveTurn(startSeconds: 12, speaker: "B", text: "Vacation next Friday."),
                ]),
        ]
        let result = ArchivePacker.pack(
            ArchivePackRequest(
                query: "ship ranking",
                jobs: jobs,
                pinnedJobIDs: ["a"],
                evidenceBudgetChars: 8_000))
        #expect(result.sources.count == 1)
        #expect(result.sources[0].stableID == "S1")
        #expect(result.sources[0].jobID == "a")
        #expect(result.packedMarkdown.contains("[S1]"))
        #expect(result.packedMarkdown.contains("Ship ranking"))
        #expect(!result.packedMarkdown.contains("Vacation"))
    }

    @Test func packerTruncatesAtTurnBoundariesAndReportsOmitted() {
        var turns: [ArchiveTurn] = []
        for i in 0..<40 {
            turns.append(ArchiveTurn(
                startSeconds: Double(i * 10),
                speaker: "S",
                text: String(repeating: "word ", count: 40) + "turn-\(i)"))
        }
        let job = ArchiveJobSummary(
            id: "long",
            displayTitle: "long-call",
            createdAt: "2026-08-08T10:00:00Z",
            notes: "Priority note about decisions",
            turns: turns)
        let result = ArchivePacker.pack(
            ArchivePackRequest(
                query: "decisions",
                jobs: [job],
                pinnedJobIDs: [],
                evidenceBudgetChars: 900))
        #expect(result.sources.count == 1)
        #expect(result.sources[0].truncated)
        #expect(result.packedMarkdown.contains("[truncated]"))
        #expect(result.packedMarkdown.contains("Priority note"))
    }

    @Test func citationParserKeepsOnlyValidSourceIDs() {
        let sources = [
            ArchiveSource(stableID: "S1", jobID: "a", displayTitle: "A", includedChars: 10, truncated: false, score: 1),
            ArchiveSource(stableID: "S2", jobID: "b", displayTitle: "B", includedChars: 10, truncated: false, score: 1),
        ]
        let text = "Decision in [S1] and maybe [S9] plus [S2]."
        let cites = CitationParser.validatedCitations(in: text, sources: sources)
        #expect(cites.map(\.stableID) == ["S1", "S2"])
        #expect(!cites.map(\.stableID).contains("S9"))
    }

    @Test func localEndpointAcceptsLoopbackAndRejectsRemote() {
        #expect(LocalEndpointPolicy.isAllowedLocalBaseURL("http://127.0.0.1:11434/v1"))
        #expect(LocalEndpointPolicy.isAllowedLocalBaseURL("http://localhost:11434/v1"))
        #expect(LocalEndpointPolicy.isAllowedLocalBaseURL("http://[::1]:11434/v1"))
        #expect(!LocalEndpointPolicy.isAllowedLocalBaseURL("https://api.openai.com/v1"))
        #expect(!LocalEndpointPolicy.isAllowedLocalBaseURL("http://evil.example/v1"))
        #expect(LocalEndpointPolicy.isAllowedRemoteBaseURL("https://api.openai.com/v1"))
        #expect(!LocalEndpointPolicy.isAllowedRemoteBaseURL("http://api.openai.com/v1"))
    }
}
