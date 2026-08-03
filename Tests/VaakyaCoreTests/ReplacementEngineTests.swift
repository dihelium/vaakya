import Foundation
import Testing
@testable import VaakyaCore

@Suite struct ReplacementEngineTests {
    private func rule(_ match: String, _ replacement: String,
                      _ kind: RuleMatchKind = .exactCI) -> ReplacementRule {
        ReplacementRule(match: match, replacement: replacement, matchKind: kind)
    }

    // MARK: - exact_ci basics

    @Test func basicExactCI() {
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("vakya", rules: rules) == "vaakya")
    }

    @Test func allCapsPreserved() {
        // Plan §5.1: VAKYA → VAAKYA
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("VAKYA", rules: rules) == "VAAKYA")
    }

    @Test func titleCasePreserved() {
        // Plan §5.1: Vakya → Vaakya
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("Vakya", rules: rules) == "Vaakya")
    }

    @Test func mixedCaseWithinSentence() {
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("I use VAKYA and vakya and Vakya daily.", rules: rules)
                == "I use VAAKYA and vaakya and Vaakya daily.")
    }

    @Test func punctuationPreserved() {
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("dictate into vakya, vaakya!", rules: rules)
                == "dictate into vaakya, vaakya!")
    }

    @Test func apostropheSuffixPreserved() {
        let rules = [rule("vakya", "vaakya")]
        #expect(ReplacementEngine.apply("vakya's settings", rules: rules) == "vaakya's settings")
    }

    // MARK: - exact_cs

    @Test func caseSensitiveOnlyMatchesExactCase() {
        let rules = [rule("Ananya", "Anaanya", .exactCS)]
        #expect(ReplacementEngine.apply("ananya vs Ananya", rules: rules) == "ananya vs Anaanya")
    }

    // MARK: - phrase

    @Test func phraseRule() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("we flew to new york today", rules: rules)
                == "we flew to New York today")
    }

    @Test func longestMatchFirst() {
        // Plan §5.1: longest-match-first for overlapping phrase rules.
        let rules = [
            rule("new york times", "NYT", .phrase),
            rule("new york", "NYC", .phrase),
        ]
        #expect(ReplacementEngine.apply("the new york times", rules: rules) == "the NYT")
    }

    @Test func phraseDoesNotMatchInsideOtherWord() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("new yorker", rules: rules) == "new yorker")
    }

    @Test func emptyPhraseRuleIsIgnored() {
        let rules = [rule("", "unexpected", .phrase)]
        #expect(ReplacementEngine.apply("keep this", rules: rules) == "keep this")
    }

    @Test func phrasePreservesTrailingPunctuation() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("visit new york, today", rules: rules)
                == "visit New York, today")
    }

    @Test func phrasePreservesSurroundingQuotes() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("say “new york” now", rules: rules)
                == "say “New York” now")
    }

    @Test func phraseDoesNotConsumeInternalPunctuation() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("new, york", rules: rules) == "new, york")
    }

    // MARK: - no-ops

    @Test func noRulesLeavesTextUntouched() {
        #expect(ReplacementEngine.apply("some text here", rules: []) == "some text here")
    }

    @Test func unmatchedTextUntouched() {
        let rules = [rule("vaakya", "vakya")]
        #expect(ReplacementEngine.apply("completely different", rules: rules) == "completely different")
    }

    @Test func whitespacePreserved() {
        let rules = [rule("vaakya", "Vaakya")]
        #expect(ReplacementEngine.apply("a  vaakya\n\nb", rules: rules) == "a  Vaakya\n\nb")
    }

    @Test func whitespaceAfterPhraseIsPreserved() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("new york\t today", rules: rules) == "New York\t today")
    }

    @Test func trailingWhitespaceIsPreserved() {
        let rules = [rule("new york", "New York", .phrase)]
        #expect(ReplacementEngine.apply("visit new york  \n", rules: rules) == "visit New York  \n")
    }

    // MARK: - overlapping single-token vs phrase (specificity)

    @Test func exactCSBeatsExactCIOnTie() {
        let rules = [
            rule("Vaakya", "VAAKYA", .exactCS),
            rule("vaakya", "vaakya-app", .exactCI),
        ]
        #expect(ReplacementEngine.apply("Vaakya", rules: rules) == "VAAKYA")
    }

    @Test func exactCIBeatsSingleWordPhraseOnTie() {
        // Review fix: specificity is explicit — a one-word phrase rule must NOT
        // beat an exact_ci rule on the same span (rawValue ordering was wrong).
        let rules = [
            rule("vaakya", "VAAKYA", .phrase),
            rule("vaakya", "vaakya-app", .exactCI),
        ]
        #expect(ReplacementEngine.apply("vaakya", rules: rules) == "vaakya-app")
    }

    // MARK: - performance sanity (plan target: <1 ms per 10k words)

    @Test func performanceTenThousandWords() {
        let words = (0..<10_000).map { "word\($0)" }
        let text = words.joined(separator: " ") + " vakya"
        let rules = [rule("vakya", "vaakya")]
        let start = DispatchTime.now().uptimeNanoseconds
        let out = ReplacementEngine.apply(text, rules: rules)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        #expect(out.hasSuffix(" vaakya"))
        // This is a regression tripwire, not a microbenchmark. Shared GitHub
        // runners can be briefly CPU-starved, so leave enough headroom to catch
        // accidental quadratic behavior without failing on scheduling noise.
        #expect(elapsedMs < 250, "10k-word pass took \(elapsedMs) ms")
    }
}
