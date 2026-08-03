import Foundation

/// User-facing settings, persisted as `config.json` (plan §4 / §6).
/// Stored locally with no account or cloud credentials.
struct AppConfig: Codable, Equatable, Sendable {
    /// CGEvent keyCode of the dictation hotkey. Default 58 is Left Option.
    var hotkeyKeyCode: Int = 58
    var hotkeyLabel: String = "Left Option"
    var doubleTapEnabled: Bool = true
    var maxHoldSeconds: Double = 90
    /// auto | unicode | paste
    var injectionMethod: String = "auto"
    /// Stage 2 (on-device LLM cleanup) — OFF by default: it can use Apple's
    /// Foundation Models which may route through Private Cloud Compute, so it
    /// requires explicit opt-in (security review finding). When enabled it is
    /// still guarded inside LLMCleanup and toggleable per session.
    var stage2Enabled: Bool = false
    var launchAtLogin: Bool = false
    /// The owner accepted FluidAudio's one-time model download. This must be
    /// durable so later launches can load the cached models without making the
    /// user repeat onboarding.
    var modelConsentGiven: Bool = false

    init() {}

    /// Decode each setting independently so adding a new config key never
    /// discards an older installation's existing preferences.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyKeyCode = try container.decodeIfPresent(Int.self, forKey: .hotkeyKeyCode) ?? 58
        hotkeyLabel = try container.decodeIfPresent(String.self, forKey: .hotkeyLabel) ?? "Left Option"
        doubleTapEnabled = try container.decodeIfPresent(Bool.self, forKey: .doubleTapEnabled) ?? true
        maxHoldSeconds = try container.decodeIfPresent(Double.self, forKey: .maxHoldSeconds) ?? 90
        injectionMethod = try container.decodeIfPresent(String.self, forKey: .injectionMethod) ?? "auto"
        stage2Enabled = try container.decodeIfPresent(Bool.self, forKey: .stage2Enabled) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        modelConsentGiven = try container.decodeIfPresent(Bool.self, forKey: .modelConsentGiven) ?? false
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Paths.configURL) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save() throws {
        try Paths.ensureAppSupport()
        let data = try JSONEncoder().encode(self)
        try data.write(to: Paths.configURL, options: [.atomic])
    }
}
