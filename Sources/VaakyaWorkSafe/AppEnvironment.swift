import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    struct StartupResult {
        let environment: AppEnvironment?
        let error: Error?
    }

    static let startup: StartupResult = {
        do {
            return StartupResult(environment: try AppEnvironment(), error: nil)
        } catch {
            return StartupResult(environment: nil, error: error)
        }
    }()

    var config: AppConfig
    let coordinator: Coordinator
    var needsOnboarding: Bool

    init() throws {
        try WorkSafePaths.ensureAppSupport()
        let config = AppConfig.load()
        self.config = config
        coordinator = Coordinator(transcriber: FluidAudioTranscriber())
        needsOnboarding = !config.modelConsentGiven
    }

    func prepareModelsWithConsent() async {
        config.modelConsentGiven = true
        do {
            try config.save()
        } catch {
            coordinator.state.lastError = "Model consent could not be saved: \(error.localizedDescription)"
            return
        }
        await coordinator.prepareModels()
        if coordinator.state.modelsReady {
            needsOnboarding = false
        }
    }
}
