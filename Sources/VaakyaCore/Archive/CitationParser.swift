import Foundation

/// A validated citation into a packed archive source.
public struct ArchiveCitation: Equatable, Codable, Sendable {
    public var stableID: String
    public var jobID: String
    public var displayTitle: String

    public init(stableID: String, jobID: String, displayTitle: String) {
        self.stableID = stableID
        self.jobID = jobID
        self.displayTitle = displayTitle
    }
}

public enum CitationParser {
    /// Extract `[S1]`, `[S2]`, … citations and keep only those present in `sources`.
    public static func validatedCitations(in text: String, sources: [ArchiveSource]) -> [ArchiveCitation] {
        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.stableID, $0) })
        let pattern = try! NSRegularExpression(pattern: #"\[(S\d+)\]"#, options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var out: [ArchiveCitation] = []
        pattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 2,
                  let idRange = Range(match.range(at: 1), in: text) else { return }
            let sid = String(text[idRange])
            guard !seen.contains(sid), let src = byID[sid] else { return }
            seen.insert(sid)
            out.append(ArchiveCitation(
                stableID: sid,
                jobID: src.jobID,
                displayTitle: src.displayTitle))
        }
        return out
    }
}
