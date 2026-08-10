import Foundation
import FluidAudio
import VaakyaCore

protocol FileDiarizer: Sendable {
    func prepare() async throws
    func diarizeFile(_ url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerInterval]
}

final class FluidAudioOfflineDiarizer: FileDiarizer, @unchecked Sendable {
    private let manager: OfflineDiarizerManager
    private var ready = false

    init(expectedSpeakerCount: Int? = nil) {
        var config = OfflineDiarizerConfig.default
        config.clustering.numSpeakers = expectedSpeakerCount
        manager = OfflineDiarizerManager(config: config)
    }

    func prepare() async throws {
        guard !ready else { return }
        try await manager.prepareModels()
        ready = true
    }

    func diarizeFile(_ url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerInterval] {
        guard ready else { throw NSError(domain: "VaakyaDiarizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Diarization models are not loaded yet."]) }
        let result = try await manager.process(url) { completed, total in
            guard total > 0 else { return }
            progressHandler(Double(completed) / Double(total))
        }
        progressHandler(1)
        return result.segments.map {
            SpeakerInterval(speakerKey: $0.speakerId,
                            startSeconds: TimeInterval($0.startTimeSeconds),
                            endSeconds: TimeInterval($0.endTimeSeconds),
                            qualityScore: $0.qualityScore)
        }
    }
}
