import Foundation

/// One speaker turn for archive packing (turn-boundary truncation).
public struct ArchiveTurn: Equatable, Sendable {
    public var startSeconds: Double
    public var speaker: String
    public var text: String

    public init(startSeconds: Double, speaker: String, text: String) {
        self.startSeconds = startSeconds
        self.speaker = speaker
        self.text = text
    }
}

/// Completed job summary ready for budgeted packing.
public struct ArchiveJobSummary: Equatable, Sendable {
    public var id: String
    public var displayTitle: String
    public var createdAt: String
    public var notes: String
    public var turns: [ArchiveTurn]

    public init(id: String, displayTitle: String, createdAt: String,
                notes: String, turns: [ArchiveTurn]) {
        self.id = id
        self.displayTitle = displayTitle
        self.createdAt = createdAt
        self.notes = notes
        self.turns = turns
    }
}

public struct ArchivePackRequest: Equatable, Sendable {
    public var query: String
    public var jobs: [ArchiveJobSummary]
    /// Empty = whole-archive mode.
    public var pinnedJobIDs: Set<String>
    public var evidenceBudgetChars: Int

    public init(query: String, jobs: [ArchiveJobSummary],
                pinnedJobIDs: Set<String>, evidenceBudgetChars: Int) {
        self.query = query
        self.jobs = jobs
        self.pinnedJobIDs = pinnedJobIDs
        self.evidenceBudgetChars = max(400, evidenceBudgetChars)
    }
}

public struct ArchiveSource: Equatable, Codable, Sendable {
    public var stableID: String
    public var jobID: String
    public var displayTitle: String
    public var includedChars: Int
    public var truncated: Bool
    public var score: Double

    public init(stableID: String, jobID: String, displayTitle: String,
                includedChars: Int, truncated: Bool, score: Double) {
        self.stableID = stableID
        self.jobID = jobID
        self.displayTitle = displayTitle
        self.includedChars = includedChars
        self.truncated = truncated
        self.score = score
    }
}

public struct ArchivePackResult: Equatable, Sendable {
    public var packedMarkdown: String
    public var sources: [ArchiveSource]
    public var omittedJobIDs: [String]
    public var packHash: String

    public init(packedMarkdown: String, sources: [ArchiveSource],
                omittedJobIDs: [String], packHash: String) {
        self.packedMarkdown = packedMarkdown
        self.sources = sources
        self.omittedJobIDs = omittedJobIDs
        self.packHash = packHash
    }
}

/// Keyword + recency budgeted packer for Archive Ask (no embeddings).
public enum ArchivePacker {
    public static func pack(_ request: ArchivePackRequest) -> ArchivePackResult {
        // Design: completed jobs with non-empty transcript turns only.
        let eligible = request.jobs.filter { !$0.turns.isEmpty }
        let scoped: [ArchiveJobSummary]
        if request.pinnedJobIDs.isEmpty {
            scoped = eligible
        } else {
            scoped = eligible.filter { request.pinnedJobIDs.contains($0.id) }
        }

        let queryTokens = tokens(request.query)
        var ranked = scoped.map { job -> (ArchiveJobSummary, Double) in
            (job, score(job: job, queryTokens: queryTokens))
        }
        ranked.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.createdAt != rhs.0.createdAt { return lhs.0.createdAt > rhs.0.createdAt }
            return lhs.0.id < rhs.0.id
        }

        let budget = request.evidenceBudgetChars
        let candidateCount = max(1, min(ranked.count, 5))
        let floor = min(1_200, max(280, budget / candidateCount))
        var remaining = budget
        var sections: [(ArchiveSource, String)] = []
        var omitted: [String] = []
        var index = 0

        for (job, jobScore) in ranked {
            if remaining < 160 {
                omitted.append(job.id)
                continue
            }
            let slotsLeft = max(1, ranked.count - sections.count)
            let allow = min(remaining, max(floor, remaining / slotsLeft))
            let built = buildSection(job: job, stableID: "S0", maxChars: allow)
            let bodyBytes = built.body.utf8.count
            // Hard bound: never accept a section that exceeds remaining budget.
            if bodyBytes > remaining {
                omitted.append(job.id)
                continue
            }
            if built.body.isEmpty {
                omitted.append(job.id)
                continue
            }
            index += 1
            let sid = "S\(index)"
            let body = built.body.replacingOccurrences(of: "## [S0]", with: "## [\(sid)]")
            remaining -= body.utf8.count
            sections.append((
                ArchiveSource(
                    stableID: sid,
                    jobID: job.id,
                    displayTitle: job.displayTitle,
                    includedChars: body.utf8.count,
                    truncated: built.truncated,
                    score: jobScore),
                body))
        }

        let packed = sections.map(\.1).joined(separator: "\n\n")
        // Assert total never exceeds budget (join separators are small; re-check).
        var finalPacked = packed
        if finalPacked.utf8.count > budget {
            // Drop trailing sections until under budget.
            var keep = sections
            while keep.count > 1,
                  keep.map(\.1).joined(separator: "\n\n").utf8.count > budget {
                if let dropped = keep.popLast() {
                    omitted.append(dropped.0.jobID)
                }
            }
            finalPacked = keep.map(\.1).joined(separator: "\n\n")
            // If still over (single oversized section), truncate string at UTF-8 boundary.
            if finalPacked.utf8.count > budget {
                finalPacked = utf8Prefix(finalPacked, maxBytes: budget - 20) + "\n…[truncated]"
                if var last = keep.last {
                    last.0 = ArchiveSource(
                        stableID: last.0.stableID,
                        jobID: last.0.jobID,
                        displayTitle: last.0.displayTitle,
                        includedChars: finalPacked.utf8.count,
                        truncated: true,
                        score: last.0.score)
                    keep = [last]
                }
            }
            let hash = packIdentityHash(finalPacked)
            return ArchivePackResult(
                packedMarkdown: finalPacked,
                sources: keep.map(\.0),
                omittedJobIDs: omitted,
                packHash: hash)
        }

        let hash = packIdentityHash(finalPacked)
        return ArchivePackResult(
            packedMarkdown: finalPacked,
            sources: sections.map(\.0),
            omittedJobIDs: omitted,
            packHash: hash)
    }

    // MARK: - internals

    private static func score(job: ArchiveJobSummary, queryTokens: Set<String>) -> Double {
        if queryTokens.isEmpty {
            return recencyBoost(job.createdAt)
        }
        var hay = job.displayTitle + "\n" + job.notes + "\n"
        for t in job.turns {
            hay += t.text + "\n"
        }
        let hayTokens = tokens(hay)
        var hits = 0
        for q in queryTokens where hayTokens.contains(q) {
            hits += 1
        }
        let overlap = Double(hits) / Double(max(1, queryTokens.count))
        return overlap * 10.0 + recencyBoost(job.createdAt)
    }

    /// Higher for more recent ISO-ish timestamps (yyyy-MM-dd…).
    private static func recencyBoost(_ createdAt: String) -> Double {
        let prefix = String(createdAt.prefix(10))
        // Lexicographic ISO dates: map to day ordinal roughly via components.
        let parts = prefix.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return 0
        }
        // Days since year 2000 (not calendar-perfect; monotonic enough for ranking).
        let days = y * 372 + m * 31 + d
        return Double(days) * 0.0001
    }

    private static func buildSection(job: ArchiveJobSummary, stableID: String, maxChars: Int)
        -> (body: String, truncated: Bool) {
        // Header always fits inside maxChars; shrink notes if needed.
        let header = """
        ## [\(stableID)] \(escapeHeader(job.displayTitle))
        job_id: \(job.id)
        created_at: \(job.createdAt)
        """
        var truncated = false
        var used = header.utf8.count
        guard used + 20 <= maxChars else {
            return ("", true)
        }

        var parts: [String] = [header]
        let notes = escapeBody(trimmed(job.notes))
        if !notes.isEmpty {
            let notesHeader = "### Notes"
            let notesHeaderCost = notesHeader.utf8.count + 1
            let roomForNotes = maxChars - used - notesHeaderCost - 30 // leave room for transcript header
            if roomForNotes > 40 {
                let noteBody: String
                if notes.utf8.count <= roomForNotes {
                    noteBody = notes
                } else {
                    noteBody = utf8Prefix(notes, maxBytes: roomForNotes - 14) + "\n…[truncated]"
                    truncated = true
                }
                parts.append(notesHeader)
                parts.append(noteBody)
                used = parts.joined(separator: "\n").utf8.count
            } else {
                truncated = true
            }
        }

        parts.append("### Transcript")
        used = parts.joined(separator: "\n").utf8.count

        var turnLines: [String] = []
        for turn in job.turns {
            let line = "[\(formatTS(turn.startSeconds))] **\(escapeHeader(turn.speaker)):** \(escapeBody(turn.text))"
            let add = line.utf8.count + 1
            if used + add > maxChars {
                truncated = true
                break
            }
            turnLines.append(line)
            used += add
        }
        // Do not mid-clip a turn; if nothing fits, mark truncated with no turn body.
        if turnLines.isEmpty {
            truncated = true
            if used + 14 <= maxChars {
                turnLines.append("…[truncated]")
                used += 14
            }
        }
        parts.append(contentsOf: turnLines)
        if truncated, !turnLines.contains("…[truncated]"), used + 14 <= maxChars {
            parts.append("…[truncated]")
        }
        let body = parts.joined(separator: "\n")
        // Final hard clamp (should rarely trigger).
        if body.utf8.count > maxChars {
            return (utf8Prefix(body, maxBytes: maxChars - 14) + "\n…[truncated]", true)
        }
        return (body, truncated)
    }

    private static func tokens(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count >= 2 })
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prevent archive text from injecting fake `## [S#]` headers.
    private static func escapeBody(_ s: String) -> String {
        s.replacingOccurrences(of: "## [S", with: "## ［S")
            .replacingOccurrences(of: "\n## [S", with: "\n## ［S")
    }

    private static func escapeHeader(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "[S", with: "［S")
    }

    private static func formatTS(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private static func utf8Prefix(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var count = 0
        var end = text.startIndex
        for i in text.indices {
            let w = text[i].utf8.count
            if count + w > maxBytes { break }
            count += w
            end = text.index(after: i)
        }
        return String(text[..<end])
    }

    private static func packIdentityHash(_ text: String) -> String {
        // FNV-1a 64 + length — pack identity / audit key (not cryptographic).
        var hash: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return String(format: "fnv1a64:%016llx:%x", hash, text.utf8.count)
    }
}
