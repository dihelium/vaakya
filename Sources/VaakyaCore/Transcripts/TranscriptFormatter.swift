import Foundation

public enum TranscriptFormatter {
    public static func plainText(
        _ turns: [TranscriptTurn],
        speakerNames: [String: String] = [:]
    ) -> String {
        turns.map { turn in
            let speaker = speakerNames[turn.speakerKey] ?? defaultSpeakerName(turn.speakerKey)
            return "\(speaker): \(turn.finalText)"
        }.joined(separator: "\n\n")
    }

    public static func markdown(
        _ turns: [TranscriptTurn],
        speakerNames: [String: String] = [:]
    ) -> String {
        turns.map { turn in
            let speaker = speakerNames[turn.speakerKey] ?? defaultSpeakerName(turn.speakerKey)
            return "**\(speaker)** *(\(timestamp(turn.startSeconds)))*\n\(turn.finalText)"
        }.joined(separator: "\n\n")
    }

    private static func defaultSpeakerName(_ key: String) -> String {
        guard key != SpeakerAttribution.unknownSpeakerKey else { return "Unknown Speaker" }
        if key.first == "S", let number = Int(key.dropFirst()) {
            return "Speaker \(number)"
        }
        return key
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}
