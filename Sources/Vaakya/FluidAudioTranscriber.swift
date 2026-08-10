import Foundation
import FluidAudio
import VaakyaCore

struct FileASRResult: Codable, Sendable {
    let text: String
    let confidence: Float
    let duration: TimeInterval
    let processingTime: TimeInterval
    let tokenTimings: [TokenTiming]
    let words: [TimedWord]
}

protocol FileTranscriber: Sendable {
    func prepare() async throws
    func transcribeFile(_ url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> FileASRResult
}

/// Abstraction over the ASR backend so the rest of the app is insulated from
/// FluidAudio's API (plan §10.6). All audio is 16 kHz mono Float32.
protocol Transcriber: Sendable {
    /// True when the model is loaded and ready to transcribe.
    func isReady() async -> Bool
    /// Download (one-time, gated by consent) and load models. Idempotent.
    func prepare() async throws
    /// Trim leading/trailing silence using Silero VAD.
    func trimSilence(_ samples: [Float]) async -> [Float]
    /// Transcribe audio and return the raw text (pre-personalization).
    func transcribe(_ samples: [Float]) async throws -> String
}

/// FluidAudio-backed transcriber: Parakeet TDT 0.6B v2 + Silero VAD (plan D5).
/// Verified against FluidAudio 0.15.5 source:
/// `AsrModels.downloadAndLoad(version: .v2)` → `AsrManager(config:models:)` +
/// `loadModels(_:)` + `transcribe(_:decoderState:)`; `VadManager` + `process(_:)`.
final class FluidAudioTranscriber: Transcriber, FileTranscriber, @unchecked Sendable {
    enum TranscriberError: LocalizedError {
        case notReady
        var errorDescription: String? {
            switch self {
            case .notReady: return "ASR models are not loaded yet."
            }
        }
    }

    private let manager: AsrManager
    private var vad: VadManager?
    private var ready = false

    init() {
        manager = AsrManager(config: .default)
    }

    func isReady() async -> Bool { ready }

    func prepare() async throws {
        guard !ready else { return }
        let models = try await AsrModels.downloadAndLoad(
            version: .v2,
            encoderPrecision: .int8,
            progressHandler: nil)
        try await manager.loadModels(models)
        // VAD is optional for v1; best-effort — failure degrades to no trimming.
        vad = try? await VadManager(config: .default)
        ready = true
    }

    func trimSilence(_ samples: [Float]) async -> [Float] {
        guard let vad else { return samples }
        guard let results = try? await vad.process(samples), !results.isEmpty else {
            return samples
        }
        // Keep only chunks where voice is active (256 ms chunks at 16 kHz).
        let chunk = 4096
        var trimmed: [Float] = []
        for (i, r) in results.enumerated() where r.isVoiceActive {
            let start = i * chunk
            let end = min(start + chunk, samples.count)
            if start < end {
                trimmed.append(contentsOf: samples[start..<end])
            }
        }
        return trimmed.isEmpty ? samples : trimmed
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard ready else { throw TranscriberError.notReady }
        // v2 always uses 2 decoder layers (verified in FluidAudio source).
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }

    func transcribeFile(_ url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> FileASRResult {
        guard ready else { throw TranscriberError.notReady }
        let progressTask = Task {
            do {
                for try await progress in await manager.transcriptionProgressStream {
                    progressHandler(progress)
                }
            } catch {
                // The transcription call reports the authoritative error.
            }
        }
        defer { progressTask.cancel() }
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        let timings = result.tokenTimings ?? []
        let words = buildWordTimings(from: timings).map {
            TimedWord(text: $0.word, startSeconds: $0.startTime, endSeconds: $0.endTime)
        }
        progressHandler(1)
        return FileASRResult(text: result.text, confidence: result.confidence,
                             duration: result.duration, processingTime: result.processingTime,
                             tokenTimings: timings, words: words)
    }
}
