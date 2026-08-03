import Foundation
import NaturalLanguage

/// Kind of a dictionary entry (plan §4 `dictionary_entries.kind`).
public enum DictionaryEntryKind: String, Codable, Sendable, Equatable, CaseIterable {
    case word
    case name
    case phrase
}

/// A ranked suggestion for the dictionary, produced by seeding (plan §5.6).
public struct SeedCandidate: Equatable, Sendable, Comparable {
    public let term: String
    public let kind: DictionaryEntryKind
    public let timesSeen: Int

    public init(term: String, kind: DictionaryEntryKind, timesSeen: Int) {
        self.term = term
        self.kind = kind
        self.timesSeen = timesSeen
    }

    public static func < (lhs: SeedCandidate, rhs: SeedCandidate) -> Bool {
        lhs.timesSeen == rhs.timesSeen ? lhs.term < rhs.term : lhs.timesSeen > rhs.timesSeen
    }
}

/// Seeds the dictionary from the user's own writing samples (plan §5.6).
///
/// Deterministic, no LLM: `NLTagger` entity recognition (`.personalName`,
/// `.organizationName`, `.placeName`) + capitalized-token frequency, filtered by a
/// stoplist of common English. Returns ranked `suggested` candidates with
/// `timesSeen` — the UI bulk-approves.
public enum WritingSampleSeeder {
    /// Common English tokens that should never become dictionary entries.
    public static let stoplist: Set<String> = {
        let common = """
        a an and are as at be but by for from had has have he her his i if in is it its
        of on or our she so than that the their them then there these they this to was
        we were what when where which who will with would you your am been being do does
        did not no yes me him us my mine yours ours we're they're don't didn't isn't
        it's i'm i've we've you've can't won't would've one two three new about into
        over under more most some any all each both few also only just very really
        """
        return Set(common.split(whereSeparator: \.isWhitespace).map(String.init))
    }()

    /// Minimum number of appearances (total, across all occurrences) to be a candidate.
    /// Pass via `minimumOccurrences:` on `candidates(from:minimumOccurrences:)`.

    /// Fraction of occurrences that must be capitalized for a plain token to qualify.
    /// Pass via `capitalizationThreshold:` on `candidates(from:minimumOccurrences:capitalizationThreshold:)`.

    public static func candidates(
        from texts: [String],
        minimumOccurrences: Int = 2,
        capitalizationThreshold: Double = 0.5
    ) -> [SeedCandidate] {
        var counts: [String: Int] = [:]          // lowercased term → total occurrences
        var capitalized: [String: Int] = [:]     // lowercased term → capitalized occurrences
        var surfaces: [String: String] = [:]     // lowercased term → first-seen surface form
        var entities: [String: Int] = [:]        // exact entity surface → occurrences

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = texts.joined(separator: "\n")

        tagger.enumerateTags(in: tagger.string!.startIndex..<tagger.string!.endIndex,
                             unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitPunctuation])
        { tag, range in
            guard let tag, tag.rawValue == NLTag.personalName.rawValue
                    || tag.rawValue == NLTag.organizationName.rawValue
                    || tag.rawValue == NLTag.placeName.rawValue else {
                return true
            }
            let term = String(tagger.string![range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty, !stoplist.contains(term.lowercased()) {
                entities[term, default: 0] += 1
            }
            return true
        }

        for text in texts {
            let tokens = text.split(whereSeparator: { $0.isWhitespace })
                .map { String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters) }
                .filter { !$0.isEmpty }
            for token in tokens {
                let lower = token.lowercased()
                guard containsLetter(token), !stoplist.contains(lower) else { continue }
                counts[lower, default: 0] += 1
                surfaces[lower] = surfaces[lower] ?? token
                if token.first?.isUppercase == true {
                    capitalized[lower, default: 0] += 1
                }
            }
        }

        var merged: [String: SeedCandidate] = [:]

        for (term, seen) in entities {
            let lower = term.lowercased()
            // Merge with frequency evidence when available.
            let total = counts[lower] ?? seen
            merged[term] = SeedCandidate(term: term, kind: .name, timesSeen: max(seen, total))
        }

        for (lower, total) in counts where total >= minimumOccurrences {
            let capFrac = Double(capitalized[lower] ?? 0) / Double(total)
            guard capFrac > capitalizationThreshold, merged[lower] == nil else { continue }
            merged[lower] = SeedCandidate(term: surfaces[lower] ?? lower, kind: .name, timesSeen: total)
        }

        return merged.values.sorted()
    }

    private static func containsLetter(_ s: String) -> Bool {
        s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }
}
