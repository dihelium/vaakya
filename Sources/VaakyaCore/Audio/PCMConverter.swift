import Foundation

/// Pure PCM conversion helpers for the recording path (plan task 1.3).
///
/// The app target's `MicRecorder` reads `AVAudioPCMBuffer` from the engine's
/// input tap and uses these to produce 16 kHz mono Float32 samples for the ASR.
/// Everything here is a pure function — round-trip tested with sine fixtures.
public enum PCMConverter {
    /// Convert any Float32 PCM layout (interleaved, arbitrary channels/rate) to
    /// 16 kHz mono Float32 — the format `AsrManager.transcribe` expects.
    public static func convertTo16kMonoFloat32(samples: [Float], inputRate: Double, inputChannels: Int) -> [Float] {
        let mono = downmix(samples: samples, channels: inputChannels)
        return resample(samples: mono, from: inputRate, to: 16_000)
    }

    /// Average interleaved channel samples into mono. `channels == 1` is identity;
    /// `channels <= 0` is treated as 1.
    public static func downmix(samples: [Float], channels: Int) -> [Float] {
        guard channels > 1 else { return samples }
        let frameCount = samples.count / channels
        var mono = [Float]()
        mono.reserveCapacity(frameCount)
        var i = 0
        while i + channels <= samples.count {
            var sum: Float = 0
            for c in 0..<channels {
                sum += samples[i + c]
            }
            mono.append(sum / Float(channels))
            i += channels
        }
        return mono
    }

    /// Linear-interpolation resampler. No-op when rates are equal.
    public static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate > 0, outputRate > 0, inputRate != outputRate, !samples.isEmpty else {
            return samples
        }
        let ratio = outputRate / inputRate
        let outCount = Int((Double(samples.count) * ratio).rounded(.down))
        var out = [Float]()
        out.reserveCapacity(outCount)
        for j in 0..<outCount {
            let pos = Double(j) / ratio
            let i0 = Int(pos)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(pos - Double(i0))
            out.append(samples[i0] * (1 - frac) + samples[i1] * frac)
        }
        return out
    }
}
