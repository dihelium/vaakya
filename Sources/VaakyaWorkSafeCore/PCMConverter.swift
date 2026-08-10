import Foundation

/// Pure conversion used by the in-memory microphone path.
public enum PCMConverter {
    public static func convertTo16kMonoFloat32(
        samples: [Float],
        inputRate: Double,
        inputChannels: Int
    ) -> [Float] {
        let mono = downmix(samples: samples, channels: inputChannels)
        return resample(samples: mono, from: inputRate, to: 16_000)
    }

    public static func downmix(samples: [Float], channels: Int) -> [Float] {
        guard channels > 1 else { return samples }
        let frameCount = samples.count / channels
        var mono: [Float] = []
        mono.reserveCapacity(frameCount)
        var index = 0
        while index + channels <= samples.count {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += samples[index + channel]
            }
            mono.append(sum / Float(channels))
            index += channels
        }
        return mono
    }

    public static func resample(
        samples: [Float],
        from inputRate: Double,
        to outputRate: Double
    ) -> [Float] {
        guard inputRate > 0, outputRate > 0, inputRate != outputRate, !samples.isEmpty else {
            return samples
        }
        let ratio = outputRate / inputRate
        let outputCount = Int((Double(samples.count) * ratio).rounded(.down))
        var output: [Float] = []
        output.reserveCapacity(outputCount)
        for position in 0..<outputCount {
            let sourcePosition = Double(position) / ratio
            let lower = Int(sourcePosition)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            output.append(samples[lower] * (1 - fraction) + samples[upper] * fraction)
        }
        return output
    }
}
