import Foundation

/// A word with the time range assigned by the ASR timing layer.
public struct TimedWord: Codable, Equatable, Sendable {
    public let text: String
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let confidence: Float?

    public init(text: String,
                startSeconds: TimeInterval,
                endSeconds: TimeInterval,
                confidence: Float? = nil) {
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.confidence = confidence
    }
}

/// A speaker interval produced by a diarizer. Speaker keys are local to one
/// imported file, for example `S1` and `S2`.
public struct SpeakerInterval: Codable, Equatable, Sendable {
    public let speakerKey: String
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let qualityScore: Float

    public init(speakerKey: String,
                startSeconds: TimeInterval,
                endSeconds: TimeInterval,
                qualityScore: Float = 0) {
        self.speakerKey = speakerKey
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.qualityScore = qualityScore
    }
}

/// A persisted, speaker-attributed transcript turn.
public struct TranscriptTurn: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let speakerKey: String
    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval
    public let rawText: String
    public var finalText: String
    public let confidence: Float?

    public init(ordinal: Int,
                speakerKey: String,
                startSeconds: TimeInterval,
                endSeconds: TimeInterval,
                rawText: String,
                finalText: String,
                confidence: Float? = nil) {
        self.ordinal = ordinal
        self.speakerKey = speakerKey
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.rawText = rawText
        self.finalText = finalText
        self.confidence = confidence
    }
}
