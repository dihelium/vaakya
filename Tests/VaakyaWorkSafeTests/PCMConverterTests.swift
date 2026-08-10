import Testing
@testable import VaakyaCore

@Suite("Work-safe PCM conversion")
struct PCMConverterTests {
    @Test("Stereo is downmixed")
    func stereoDownmix() {
        #expect(PCMConverter.downmix(samples: [1, 3, 5, 7], channels: 2) == [2, 6])
    }

    @Test("Empty samples remain empty")
    func emptyInput() {
        #expect(PCMConverter.convertTo16kMonoFloat32(
            samples: [], inputRate: 48_000, inputChannels: 1
        ).isEmpty)
    }
}
