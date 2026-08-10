import Foundation

public enum TranscriptJobStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case paused
    case cancelled
    case failed
    case completed
}

public enum TranscriptActiveStage: String, Codable, Equatable, Sendable {
    case idle
    case preparingASR
    case transcribing
    case preparingDiarizer
    case diarizing
    case aligning
}

public enum TranscriptCompletedStage: String, Codable, Equatable, Sendable {
    case none
    case asr
    case diarization
    case alignment
}

public enum TranscriptJobStateError: Error, Equatable, Sendable {
    case invalidTransition(from: TranscriptJobStatus, active: TranscriptActiveStage, event: String)
    case stageOutOfOrder(expected: String, received: String)
}

public struct TranscriptJobState: Codable, Equatable, Sendable {
    public private(set) var status: TranscriptJobStatus = .queued
    public private(set) var activeStage: TranscriptActiveStage = .idle
    public private(set) var completedStage: TranscriptCompletedStage = .none
    public private(set) var progress: Double = 0
    public private(set) var errorMessage: String?

    public init() {}

    public mutating func begin(_ stage: TranscriptActiveStage) throws {
        let canContinueCurrentStage = status == .running
            && ((activeStage == .preparingASR && stage == .transcribing)
                || (activeStage == .preparingDiarizer && stage == .diarizing))
        guard status == .queued || status == .paused || status == .failed || canContinueCurrentStage else {
            throw TranscriptJobStateError.invalidTransition(
                from: status, active: activeStage, event: "begin")
        }
        let allowed: Bool
        switch (completedStage, activeStage, stage) {
        case (.none, .idle, .preparingASR),
             (.none, .preparingASR, .transcribing),
             (.none, .preparingASR, .preparingASR),
             (.none, .transcribing, .transcribing),
             (.asr, .idle, .preparingDiarizer),
             (.asr, .preparingDiarizer, .diarizing),
             (.asr, .preparingDiarizer, .preparingDiarizer),
             (.asr, .diarizing, .diarizing),
             (.diarization, .idle, .aligning):

            allowed = true
        default:
            allowed = false
        }
        guard allowed else {
            throw TranscriptJobStateError.stageOutOfOrder(
                expected: expectedNextStageDescription,
                received: stage.rawValue)
        }
        activeStage = stage
        status = .running
        errorMessage = nil
        progress = 0
    }

    public mutating func finish(_ stage: TranscriptActiveStage) throws {
        guard status == .running, activeStage == stage else {
            throw TranscriptJobStateError.invalidTransition(
                from: status, active: activeStage, event: "finish")
        }
        switch stage {
        case .transcribing:
            completedStage = .asr
        case .diarizing:
            completedStage = .diarization
        case .aligning:
            completedStage = .alignment
        case .idle, .preparingASR, .preparingDiarizer:
            throw TranscriptJobStateError.stageOutOfOrder(
                expected: "a processing stage", received: stage.rawValue)
        }
        activeStage = .idle
        progress = 1
        status = completedStage == .alignment ? .completed : .queued
    }

    public mutating func updateProgress(_ value: Double) {
        progress = min(1, max(0, value))
    }

    public mutating func pause() {
        guard status == .running else { return }
        status = .paused
    }

    public mutating func cancel() {
        guard status != .completed else { return }
        status = .cancelled
    }

    public mutating func fail(_ message: String) {
        guard status != .completed else { return }
        status = .failed
        errorMessage = message
    }

    /// Converts an interrupted in-memory run into resumable queued work while
    /// retaining the last completed stage and the active stage to retry.
    public mutating func recover() {
        guard status != .completed else { return }
        status = .queued
        errorMessage = nil
    }

    private var expectedNextStageDescription: String {
        switch completedStage {
        case .none: return "preparingASR"
        case .asr: return "preparingDiarizer"
        case .diarization: return "aligning"
        case .alignment: return "complete"
        }
    }
}
