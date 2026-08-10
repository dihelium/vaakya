import Testing
@testable import VaakyaCore

@Suite struct EmptyAudioWatchdogTests {
    @Test func emptyAudioTimesOutAtConfiguredInterval() {
        var watchdog = EmptyAudioWatchdog(timeoutSeconds: 90, startedAt: 10)
        watchdog.observe(samples: [0, 0, 0], at: 80)

        #expect(!watchdog.hasTimedOut(at: 99.999))
        #expect(watchdog.hasTimedOut(at: 100))
    }

    @Test func meaningfulAudioRestartsTimeoutWindow() {
        var watchdog = EmptyAudioWatchdog(timeoutSeconds: 90, startedAt: 0)
        watchdog.observe(samples: [0.02, -0.02], at: 80)

        #expect(!watchdog.hasTimedOut(at: 169.999))
        #expect(watchdog.hasTimedOut(at: 170))
    }

    @Test func subthresholdInputDoesNotRestartTimeoutWindow() {
        var watchdog = EmptyAudioWatchdog(timeoutSeconds: 90,
                                          amplitudeThreshold: 0.01,
                                          startedAt: 0)
        watchdog.observe(samples: [0.005, -0.005], at: 80)

        #expect(watchdog.hasTimedOut(at: 90))
    }

    @Test func rmsUsesBothPositiveAndNegativeSamples() {
        let rms = EmptyAudioWatchdog.rmsAmplitude(of: [0.3, -0.4])
        #expect(abs(rms - 0.353_553) < 0.000_001)
    }

    @Test func nonpositiveTimeoutDisablesFallback() {
        let watchdog = EmptyAudioWatchdog(timeoutSeconds: 0, startedAt: 0)
        #expect(!watchdog.hasTimedOut(at: 10_000))
    }
}
