import AppKit
import Foundation
import VaakyaCore

/// Shared app environment injected into every SwiftUI scene: database, config,
/// coordinator (dictation loop), and the observable UI state.
@MainActor
@Observable
final class AppEnvironment {
    /// Created exactly once, on the main actor, at first access (avoids the
    /// scene-body-vs-didFinishLaunching race). Views inject this directly.
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

    let db: VaakyaDatabase
    var config: AppConfig
    let coordinator: Coordinator
    var needsOnboarding: Bool

    init() throws {
        try Paths.ensureAppSupport()
        let db = try VaakyaDatabase(path: Paths.dbURL.path)
        let config = AppConfig.load()

        let transcriber: any Transcriber = FluidAudioTranscriber()
        var cleanup: (any CleanupModel)?
        if #available(macOS 26.0, *), FMAdapter.isAvailable {
            cleanup = FMAdapter()
        }
        let coordinator = Coordinator(config: config, db: db,
                                      transcriber: transcriber,
                                      cleanupModel: cleanup)
        self.db = db
        self.config = config
        self.coordinator = coordinator
        needsOnboarding = !config.modelConsentGiven
    }

    func saveConfig() {
        config.stage2Enabled = coordinator.stage2Gate.value
        do {
            try config.save()
        } catch {
            coordinator.state.lastError = "Settings couldn't be saved: \(error.localizedDescription)"
        }
    }

    /// Persist consent before FluidAudio is allowed to prepare or download
    /// anything. If preparation fails, consent remains valid and the next
    /// launch can retry using the same consent gate.
    func prepareModelsWithConsent() async {
        config.modelConsentGiven = true
        do {
            try config.save()
        } catch {
            coordinator.state.lastError = "Model consent couldn't be saved: \(error.localizedDescription)"
            return
        }
        needsOnboarding = false
        await coordinator.prepareModels()
    }
}
