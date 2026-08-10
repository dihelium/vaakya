import AVFoundation
import Foundation
import VaakyaCore

/// Holds microphone samples in memory only for the duration of one dictation.
final class MicRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noInput
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .noInput: return "No audio input device is available."
            case .alreadyRecording: return "Vaakya is already recording."
            }
        }
    }

    enum MicPermission: Equatable {
        case undetermined
        case denied
        case granted
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var recording = false

    static var micStatus: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    static func requestMicPermission(_ completion: @escaping @Sendable (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission(completionHandler: completion)
    }

    func start() throws {
        lock.lock()
        let alreadyRecording = recording
        lock.unlock()
        guard !alreadyRecording else { throw RecorderError.alreadyRecording }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.noInput
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let raw = self.float32Samples(from: buffer)
            let converted = PCMConverter.convertTo16kMonoFloat32(
                samples: raw,
                inputRate: format.sampleRate,
                inputChannels: Int(format.channelCount)
            )
            self.lock.lock()
            if self.recording {
                self.samples.append(contentsOf: converted)
            }
            self.lock.unlock()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.lock()
        recording = true
        lock.unlock()
    }

    func stop() -> [Float] {
        lock.lock()
        let wasRecording = recording
        recording = false
        lock.unlock()
        guard wasRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: false)
        return result
    }

    private func float32Samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var output: [Float] = []
        output.reserveCapacity(frames * channels)
        if buffer.format.isInterleaved {
            output.append(contentsOf: UnsafeBufferPointer(
                start: channelData[0],
                count: frames * channels
            ))
        } else {
            for frame in 0..<frames {
                for channel in 0..<channels {
                    output.append(channelData[channel][frame])
                }
            }
        }
        return output
    }
}
