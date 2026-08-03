import Foundation
import Testing
@testable import VaakyaCore

@Suite struct PCMConverterTests {
    // MARK: - downmix

    @Test func downmixStereoToMono() {
        let stereo: [Float] = [0.5, -0.5, 1.0, -1.0, 0.25, 0.75]
        let mono = PCMConverter.downmix(samples: stereo, channels: 2)
        #expect(mono.count == 3)
        #expect(mono[0] == 0)
        #expect(mono[1] == 0)
        #expect(abs(mono[2] - 0.5) < 1e-6)
    }

    @Test func downmixMonoIsIdentity() {
        let mono: [Float] = [0.1, 0.2, 0.3]
        #expect(PCMConverter.downmix(samples: mono, channels: 1) == mono)
    }

    @Test func downmixChannelsIsZero() {
        let mono: [Float] = [0.1, 0.2]
        #expect(PCMConverter.downmix(samples: mono, channels: 0) == mono)
    }

    // MARK: - resample

    @Test func resampleToHigherRateKeepsLength() {
        // 1 s at 16 kHz → 48 kHz.
        let input: [Float] = (0..<16_000).map { i -> Float in
            let phase = 2.0 * Double.pi * 440.0 * Double(i) / 16_000.0
            return Float(sin(phase)) * 0.5
        }
        let out = PCMConverter.resample(samples: input, from: 16_000, to: 48_000)
        #expect(abs(out.count - 48_000) <= 10)
    }

    @Test func resampleRoundTripPreservesFrequency() {
        // 440 Hz sine at 16 kHz → up to 48 kHz → down to 16 kHz.
        let freq = 440.0
        let rate = 16_000.0
        let input: [Float] = (0..<16_000).map { i -> Float in
            let phase = 2.0 * Double.pi * freq * Double(i) / rate
            return Float(sin(phase))
        }
        let up = PCMConverter.resample(samples: input, from: rate, to: 48_000)
        let roundTripped = PCMConverter.resample(samples: up, from: 48_000, to: rate)

        // Same length (±1 sample).
        #expect(abs(roundTripped.count - input.count) <= 1)

        // Cross-correlate a window against the original sine to confirm the
        // dominant frequency is preserved (correlation near 1).
        let window = 4_000
        let a = Array(input[0..<window])
        let b = Array(roundTripped[0..<window])
        let corr = crossCorrelation(a, b)
        #expect(corr > 0.95, "expected near-identical waveform, corr=\(corr)")
    }

    @Test func resampleNoOpAtSameRate() {
        let input: [Float] = [0.1, -0.2, 0.3]
        #expect(PCMConverter.resample(samples: input, from: 16_000, to: 16_000) == input)
    }

    @Test func resampleEmpty() {
        #expect(PCMConverter.resample(samples: [], from: 48_000, to: 16_000).isEmpty)
    }

    // MARK: - combined pipeline shape (sine fixture → 16 kHz mono Float32)

    @Test func convertTo16kMonoFrom48kStereo() {
        let rate = 48_000.0
        let freq = 440.0
        let n = Int(rate * 1.0)
        var interleaved: [Float] = []
        interleaved.reserveCapacity(n * 2)
        for i in 0..<n {
            let phase = 2.0 * Double.pi * freq * Double(i) / rate
            let v = Float(sin(phase)) * 0.5
            interleaved.append(v)  // L
            interleaved.append(v)  // R
        }
        let out = PCMConverter.convertTo16kMonoFloat32(samples: interleaved,
                                                       inputRate: rate, inputChannels: 2)
        #expect(abs(out.count - 16_000) <= 10)
        #expect(abs((out.map { abs($0) }.max() ?? 0) - 0.5) < 0.05)
    }

    // MARK: - helpers

    private func crossCorrelation(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        let meanA = a.reduce(0, +) / Float(n)
        let meanB = b.reduce(0, +) / Float(n)
        var num = 0.0, denA = 0.0, denB = 0.0
        for i in 0..<n {
            let da = Double(a[i] - meanA)
            let db = Double(b[i] - meanB)
            num += da * db
            denA += da * da
            denB += db * db
        }
        let denom = (denA * denB).squareRoot()
        return denom > 0 ? num / denom : 1
    }
}
