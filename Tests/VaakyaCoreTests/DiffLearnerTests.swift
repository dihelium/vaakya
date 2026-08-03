import Testing
@testable import VaakyaCore

@Suite struct DiffLearnerTests {
    // MARK: - empty and imbalanced inputs

    @Test func emptyInputsProduceAnEmptyDiff() {
        let r = DiffLearner.diff(asrText: "", editedText: "")
        #expect(r.candidates.isEmpty)
        #expect(r.substitutionCount == 0)
        #expect(r.insertionCount == 0)
        #expect(r.deletionCount == 0)
        #expect(r.asrTokenCount == 0)
        #expect(r.editedTokenCount == 0)
        #expect(!r.isWholesaleRewrite)
    }

    @Test func whitespaceOnlyOriginalCountsEditedWordsAsInsertions() {
        let r = DiffLearner.diff(asrText: " \t\n ", editedText: "hello world")
        #expect(r.candidates.isEmpty)
        #expect(r.substitutionCount == 0)
        #expect(r.insertionCount == 2)
        #expect(r.deletionCount == 0)
        #expect(r.asrTokenCount == 0)
        #expect(r.editedTokenCount == 2)
    }

    @Test func veryUnequalInputsRemainSafeAndCountTheLongTail() {
        let edited = (["keep"] + (0..<100).map { "word\($0)" }).joined(separator: " ")
        let r = DiffLearner.diff(asrText: "keep", editedText: edited)
        #expect(r.candidates.isEmpty)
        #expect(r.substitutionCount == 0)
        #expect(r.insertionCount == 100)
        #expect(r.deletionCount == 0)
        #expect(r.asrTokenCount == 1)
        #expect(r.editedTokenCount == 101)
    }

    // MARK: - substitutions

    @Test func caseOnlySubstitutionBecomesExactCS() throws {
        // Plan §5.3: case-only mismatch → exact_cs candidate (the names use-case).
        let r = DiffLearner.diff(asrText: "call ananya", editedText: "call Ananya")
        let candidate = try #require(r.candidates.first)
        #expect(candidate.match == "ananya")
        #expect(candidate.replacement == "Ananya")
        #expect(candidate.matchKind == .exactCS)
    }

    @Test func contentSubstitutionBecomesExactCI() {
        let r = DiffLearner.diff(asrText: "use vakya", editedText: "use vaakya")
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].match == "vakya")
        #expect(r.candidates[0].replacement == "vaakya")
        #expect(r.candidates[0].matchKind == .exactCI)
    }

    @Test func surroundingPunctuationIsExcludedFromLearnedRule() {
        let r = DiffLearner.diff(asrText: "use vakya.", editedText: "use vaakya.")
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].match == "vakya")
        #expect(r.candidates[0].replacement == "vaakya")
    }

    @Test func punctuationOnlyEditProducesNoRule() {
        let r = DiffLearner.diff(asrText: "hello world", editedText: "hello, world!")
        #expect(r.candidates.isEmpty)
        #expect(r.substitutionCount == 0)
    }

    @Test func twoTokenSubstitutionSpanBecomesPhraseRule() {
        let r = DiffLearner.diff(asrText: "go to new yark", editedText: "go to New York")
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].match == "new yark")
        #expect(r.candidates[0].replacement == "New York")
        #expect(r.candidates[0].matchKind == .phrase)
        #expect(r.candidates[0].spanTokens == 2)
    }

    @Test func threeTokenSpanAllowed() {
        let r = DiffLearner.diff(asrText: "x y z go", editedText: "a b c go")
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].spanTokens == 3)
        #expect(r.candidates[0].match == "x y z")
        #expect(r.candidates[0].replacement == "a b c")
        #expect(r.candidates[0].matchKind == .phrase)
    }

    @Test func independentSubstitutionsWithinSentenceBothProduceRules() {
        // DP matches "is" between the two substitutions, so two separate 1-token rules.
        let r = DiffLearner.diff(asrText: "my nam is wrong", editedText: "my name is right")
        #expect(r.substitutionCount == 2)
        #expect(r.candidates.count == 2)
        #expect(r.candidates.allSatisfy { $0.spanTokens == 1 })
    }

    @Test func fourTokenSpanProducedNoRule() {
        let r = DiffLearner.diff(asrText: "a b c d foo", editedText: "w x y z foo")
        #expect(r.candidates.isEmpty)
    }

    // MARK: - wholesale rewrites

    @Test func wholesaleRewriteIgnored() {
        // >30% of tokens changed teaches nothing.
        let r = DiffLearner.diff(asrText: "the quick brown fox jumps", editedText: "the slow green cat walks")
        #expect(r.isWholesaleRewrite)
        #expect(r.candidates.isEmpty)
    }

    // MARK: - insertions / deletions

    @Test func insertionProducesNoRule() {
        let r = DiffLearner.diff(asrText: "meet at noon", editedText: "meet at noon sharp")
        #expect(r.candidates.isEmpty)
        #expect(r.insertionCount == 1)
    }

    @Test func deletionProducesNoRule() {
        let r = DiffLearner.diff(asrText: "see you tomorrow", editedText: "see tomorrow")
        #expect(r.candidates.isEmpty)
        #expect(r.deletionCount == 1)
    }

    @Test func identicalTextProducesNothing() {
        let r = DiffLearner.diff(asrText: "hello world", editedText: "hello world")
        #expect(r.candidates.isEmpty)
        #expect(r.substitutionCount == 0)
        #expect(!r.isWholesaleRewrite)
    }

    // MARK: - mixed

    @Test func deletionSeparatesSubstitutionSpans() {
        // Unique-minimum alignment: sub(vakya→vaakya), match(please), del(now).
        let r = DiffLearner.diff(asrText: "vakya please now", editedText: "vaakya please")
        let candidate = r.candidates.first
        #expect(candidate?.match == "vakya")
        #expect(candidate?.replacement == "vaakya")
        #expect(r.deletionCount == 1)
        #expect(!r.isWholesaleRewrite) // a short fix + one deletion is not a rewrite
    }

    @Test func twoIndependentSubstitutionsBothProduceCandidates() {
        let r = DiffLearner.diff(asrText: "vakya is better than vrota",
                                 editedText: "vaakya is better than vaakya")
        #expect(r.candidates.count == 2)
        #expect(r.substitutionCount == 2)
        #expect(!r.isWholesaleRewrite) // short isolated spans are not rewrites
    }
}
