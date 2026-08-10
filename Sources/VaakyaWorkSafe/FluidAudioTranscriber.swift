import FluidAudio
import Foundation

protocol Transcriber: Sendable {
    func prepare() async throws
    func trimSilence(_ samples: [Float]) async -> [Float]
    func transcribe(_ samples: [Float]) async throws -> String
}

/// The only network-capable dependency path: FluidAudio downloads the speech
/// model after explicit consent, then transcription runs locally.
final class FluidAudioTranscriber: Transcriber, @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case notReady

        var errorDescription: String? {
            "The local speech model is not ready."
        }
    }

    private let manager = AsrManager(config: .default)
    private var vad: VadManager?
    private var ready = false

    func prepare() async throws {
        guard !ready else { return }
        let models = try await AsrModels.downloadAndLoad(
            version: .v2,
            encoderPrecision: .int8,
            progressHandler: nil
        )
        try await manager.loadModels(models)
        vad = try? await VadManager(config: .default)
        ready = true
    }

    func trimSilence(_ samples: [Float]) async -> [Float] {
        guard let vad,
              let results = try? await vad.process(samples),
              !results.isEmpty else {
            return samples
        }

        let chunkSize = 4096
        var trimmed: [Float] = []
        for (index, result) in results.enumerated() where result.isVoiceActive {
            let start = index * chunkSize
            let end = min(start + chunkSize, samples.count)
            if start < end {
                trimmed.append(contentsOf: samples[start..<end])
            }
        }
        return trimmed.isEmpty ? samples : trimmed
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard ready else { throw TranscriberError.notReady }
        var decoderState = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &decoderState).text
    }
}
