import Foundation

/// Tracks how long a recording has gone without meaningful microphone input.
///
/// This is deliberately an inactivity watchdog, not a recording-duration cap.
/// Every buffer containing meaningful audio restarts the timeout window.
public struct EmptyAudioWatchdog: Sendable {
    public static let defaultAmplitudeThreshold: Float = 0.001

    public let timeoutSeconds: TimeInterval
    public let amplitudeThreshold: Float
    private var lastMeaningfulAudioTime: TimeInterval

    public init(timeoutSeconds: TimeInterval,
                amplitudeThreshold: Float = Self.defaultAmplitudeThreshold,
                startedAt: TimeInterval) {
        self.timeoutSeconds = timeoutSeconds
        self.amplitudeThreshold = max(0, amplitudeThreshold)
        lastMeaningfulAudioTime = startedAt
    }

    /// Treat a buffer as meaningful when its RMS amplitude clears the configured
    /// floor. RMS avoids letting a single click keep an abandoned latch alive.
    public mutating func observe(samples: [Float], at time: TimeInterval) {
        guard Self.rmsAmplitude(of: samples) > amplitudeThreshold else { return }
        lastMeaningfulAudioTime = time
    }

    public func hasTimedOut(at time: TimeInterval) -> Bool {
        guard timeoutSeconds > 0 else { return false }
        return time - lastMeaningfulAudioTime >= timeoutSeconds
    }

    public static func rmsAmplitude(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var squaredSum = 0.0
        var finiteSampleCount = 0
        for sample in samples where sample.isFinite {
            let value = Double(sample)
            squaredSum += value * value
            finiteSampleCount += 1
        }
        guard finiteSampleCount > 0 else { return 0 }
        return Float((squaredSum / Double(finiteSampleCount)).squareRoot())
    }
}
