import Testing
@testable import VaakyaCore

@Suite struct WritingSampleSeederTests {
    @Test func entityNamesRankedByFrequency() {
        // "Rahul" appears twice as a personal name → top candidate.
        let corpus = [
            "I met Rahul at the office yesterday.",
            "Rahul and I discussed the roadmap. Rahul is leading the team.",
        ]
        let candidates = WritingSampleSeeder.candidates(from: corpus)
        #expect(!candidates.isEmpty)
        guard let rahul = candidates.first(where: { $0.term == "Rahul" }) else {
            Issue.record("expected Rahul in \(candidates)")
            return
        }
        #expect(rahul.kind == .name)
        #expect(rahul.timesSeen >= 2)
        // Sorted by timesSeen descending.
        #expect(candidates == candidates.sorted { a, b in
            a.timesSeen == b.timesSeen ? a.term < b.term : a.timesSeen > b.timesSeen
        })
    }

    @Test func capitalizedTokenFrequencyPicksRecurringCapitalizedWord() {
        // "Foobar" appears capitalized twice → suggested name candidate.
        let corpus = ["Foobar is the codename.", "We shipped Foobar this week."]
        let candidates = WritingSampleSeeder.candidates(from: corpus)
        #expect(candidates.contains { $0.term == "Foobar" && $0.kind == .name })
    }

    @Test func commonEnglishWordsExcludedByStoplist() {
        let corpus = ["The plan is ready.", "The team approved the plan.", "The end."]
        let candidates = WritingSampleSeeder.candidates(from: corpus)
        #expect(!candidates.contains { $0.term == "The" })
        #expect(!candidates.contains { $0.term == "the" })
    }

    @Test func singleOccurrenceNotRanked() {
        let corpus = ["ZebraicQuux appears exactly once here."]
        let candidates = WritingSampleSeeder.candidates(from: corpus)
        #expect(!candidates.contains { $0.term == "ZebraicQuux" })
    }

    @Test func emptyCorpusYieldsNothing() {
        #expect(WritingSampleSeeder.candidates(from: []).isEmpty)
        #expect(WritingSampleSeeder.candidates(from: ["", "   "]).isEmpty)
    }

    @Test func deterministicOutput() {
        let corpus = ["We met Neha in Pune.", "Neha joined Pune office.", "Pune is hot."]
        #expect(WritingSampleSeeder.candidates(from: corpus)
                == WritingSampleSeeder.candidates(from: corpus))
    }
}
