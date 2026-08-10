import Foundation

/// Pure word-to-speaker attribution and turn coalescing.
public enum SpeakerAttribution {
    public static let unknownSpeakerKey = "unknown"

    public static func makeTurns(
        words: [TimedWord],
        segments: [SpeakerInterval],
        nearestSpeakerToleranceSeconds: TimeInterval = 0.5,
        maximumTurnGapSeconds: TimeInterval = 1.5
    ) -> [TranscriptTurn] {
        guard !words.isEmpty else { return [] }

        var turns: [TranscriptTurn] = []
        var currentWords: [TimedWord] = []
        var currentSpeaker: String?

        func flush() {
            guard let currentSpeaker, !currentWords.isEmpty else { return }
            let start = currentWords.map(\.startSeconds).min() ?? 0
            let end = currentWords.map(\.endSeconds).max() ?? start
            let confidenceValues = currentWords.compactMap(\.confidence)
            let confidence = confidenceValues.isEmpty
                ? nil
                : confidenceValues.reduce(0, +) / Float(confidenceValues.count)
            let text = joinWords(currentWords.map(\.text))
            turns.append(TranscriptTurn(
                ordinal: turns.count,
                speakerKey: currentSpeaker,
                startSeconds: start,
                endSeconds: end,
                rawText: text,
                finalText: text,
                confidence: confidence))
            currentWords.removeAll(keepingCapacity: true)
        }

        for word in words {
            let speaker = speakerKey(
                for: word,
                in: segments,
                nearestTolerance: nearestSpeakerToleranceSeconds)
            let startsNewTurn: Bool
            if let currentSpeaker {
                let gap = word.startSeconds - (currentWords.last?.endSeconds ?? word.startSeconds)
                startsNewTurn = currentSpeaker != speaker || gap > maximumTurnGapSeconds
            } else {
                startsNewTurn = false
            }
            if startsNewTurn {
                flush()
            }
            currentSpeaker = speaker
            currentWords.append(word)
        }
        flush()
        return turns
    }

    private static func speakerKey(
        for word: TimedWord,
        in segments: [SpeakerInterval],
        nearestTolerance: TimeInterval
    ) -> String {
        guard !segments.isEmpty else { return unknownSpeakerKey }
        let wordStart = min(word.startSeconds, word.endSeconds)
        let wordEnd = max(word.startSeconds, word.endSeconds)

        let rankedOverlaps = segments.compactMap { segment -> (SpeakerInterval, TimeInterval)? in
            let overlap = max(0, min(wordEnd, segment.endSeconds) - max(wordStart, segment.startSeconds))
            return overlap > 0 ? (segment, overlap) : nil
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.qualityScore != rhs.0.qualityScore {
                return lhs.0.qualityScore > rhs.0.qualityScore
            }
            return lhs.0.speakerKey < rhs.0.speakerKey
        }
        if let best = rankedOverlaps.first {
            return best.0.speakerKey
        }

        let nearest = segments.map { segment -> (SpeakerInterval, TimeInterval) in
            let distance: TimeInterval
            if wordEnd < segment.startSeconds {
                distance = segment.startSeconds - wordEnd
            } else if wordStart > segment.endSeconds {
                distance = wordStart - segment.endSeconds
            } else {
                distance = 0
            }
            return (segment, distance)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.qualityScore != rhs.0.qualityScore {
                return lhs.0.qualityScore > rhs.0.qualityScore
            }
            return lhs.0.speakerKey < rhs.0.speakerKey
        }
        guard let best = nearest.first, best.1 <= nearestTolerance else {
            return unknownSpeakerKey
        }
        return best.0.speakerKey
    }

    private static func joinWords(_ words: [String]) -> String {
        var result = ""
        for rawWord in words {
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            if result.isEmpty || isPunctuationOnly(word) || word.first == "'" || word.first == "’" {
                result += word
            } else {
                result += " " + word
            }
        }
        return result
    }

    private static func isPunctuationOnly(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }
}
