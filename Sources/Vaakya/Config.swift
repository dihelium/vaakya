import Foundation
import VaakyaCore

/// User-facing settings, persisted as `config.json` (plan §4 / §6).
/// Stored locally with no account or cloud credentials.
struct AppConfig: Codable, Equatable, Sendable {
    /// CGEvent keyCode of the dictation hotkey. Default 58 is Left Option.
    var hotkeyKeyCode: Int = 58
    var hotkeyLabel: String = "Left Option"
    var doubleTapEnabled: Bool = true
    /// Legacy persisted key name. This is the empty-audio fallback interval for
    /// latched recording, not a maximum recording duration.
    var maxHoldSeconds: Double = 90
    var emptyAudioTimeoutSeconds: Double {
        get { maxHoldSeconds }
        set { maxHoldSeconds = newValue }
    }
    /// auto | unicode | paste
    var injectionMethod: String = "auto"
    /// Stage 2 (on-device LLM cleanup) — OFF by default.
    var stage2Enabled: Bool = false
    var launchAtLogin: Bool = false
    var modelConsentGiven: Bool = false
    var diarizationModelConsentGiven: Bool = false

    /// Master switch for B1 text egress (Codex / Remote). Local does not need this.
    var lensEgressEnabled: Bool = false

    /// Shared runner for Lenses + Archive Ask: `codex` | `local` | `remote`.
    var selectedLLMRunner: String = "local"

    var localBaseURL: String = "http://127.0.0.1:11434/v1"
    var localModel: String = "llama3.2"
    var remoteBaseURL: String = "https://api.openai.com/v1"
    var remoteModel: String = "gpt-4o"
    /// Optional absolute path to the `codex` binary; empty = auto-discover.
    var lensCodexPath: String = ""

    // MARK: - Legacy aliases (kept in JSON for older installs / tools)

    /// Legacy: `openai` | `codex` — rewritten from selectedLLMRunner on encode.
    var lensProvider: String = "openai"
    var lensAPIBase: String = "http://127.0.0.1:11434/v1"
    var lensModel: String = "llama3.2"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case hotkeyKeyCode, hotkeyLabel, doubleTapEnabled, maxHoldSeconds
        case injectionMethod, stage2Enabled, launchAtLogin
        case modelConsentGiven, diarizationModelConsentGiven
        case lensEgressEnabled, selectedLLMRunner
        case localBaseURL, localModel, remoteBaseURL, remoteModel, lensCodexPath
        case lensProvider, lensAPIBase, lensModel
    }

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
        diarizationModelConsentGiven = try container.decodeIfPresent(Bool.self, forKey: .diarizationModelConsentGiven) ?? false
        lensEgressEnabled = try container.decodeIfPresent(Bool.self, forKey: .lensEgressEnabled) ?? false
        lensCodexPath = try container.decodeIfPresent(String.self, forKey: .lensCodexPath) ?? ""

        let legacyProvider = try container.decodeIfPresent(String.self, forKey: .lensProvider) ?? "openai"
        let legacyBase = try container.decodeIfPresent(String.self, forKey: .lensAPIBase)
            ?? "http://127.0.0.1:11434/v1"
        let legacyModel = try container.decodeIfPresent(String.self, forKey: .lensModel) ?? "llama3.2"

        localBaseURL = try container.decodeIfPresent(String.self, forKey: .localBaseURL)
            ?? "http://127.0.0.1:11434/v1"
        localModel = try container.decodeIfPresent(String.self, forKey: .localModel) ?? "llama3.2"
        remoteBaseURL = try container.decodeIfPresent(String.self, forKey: .remoteBaseURL) ?? legacyBase
        remoteModel = try container.decodeIfPresent(String.self, forKey: .remoteModel) ?? legacyModel

        if let runner = try container.decodeIfPresent(String.self, forKey: .selectedLLMRunner) {
            selectedLLMRunner = Self.normalizeRunner(runner)
        } else {
            // Migrate old lensProvider.
            switch legacyProvider.lowercased() {
            case "openai":
                if LocalEndpointPolicy.isAllowedLocalBaseURL(legacyBase) {
                    selectedLLMRunner = "local"
                    localBaseURL = legacyBase
                    localModel = legacyModel
                } else {
                    selectedLLMRunner = "remote"
                    remoteBaseURL = legacyBase
                    remoteModel = legacyModel
                }
            case "codex":
                selectedLLMRunner = "codex"
            default:
                selectedLLMRunner = "local"
            }
        }

        // Keep legacy mirrors consistent for tools that still read them.
        syncLegacyMirrors()
    }

    func encode(to encoder: Encoder) throws {
        var c = self
        c.syncLegacyMirrors()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(c.hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(c.hotkeyLabel, forKey: .hotkeyLabel)
        try container.encode(c.doubleTapEnabled, forKey: .doubleTapEnabled)
        try container.encode(c.maxHoldSeconds, forKey: .maxHoldSeconds)
        try container.encode(c.injectionMethod, forKey: .injectionMethod)
        try container.encode(c.stage2Enabled, forKey: .stage2Enabled)
        try container.encode(c.launchAtLogin, forKey: .launchAtLogin)
        try container.encode(c.modelConsentGiven, forKey: .modelConsentGiven)
        try container.encode(c.diarizationModelConsentGiven, forKey: .diarizationModelConsentGiven)
        try container.encode(c.lensEgressEnabled, forKey: .lensEgressEnabled)
        try container.encode(c.selectedLLMRunner, forKey: .selectedLLMRunner)
        try container.encode(c.localBaseURL, forKey: .localBaseURL)
        try container.encode(c.localModel, forKey: .localModel)
        try container.encode(c.remoteBaseURL, forKey: .remoteBaseURL)
        try container.encode(c.remoteModel, forKey: .remoteModel)
        try container.encode(c.lensCodexPath, forKey: .lensCodexPath)
        try container.encode(c.lensProvider, forKey: .lensProvider)
        try container.encode(c.lensAPIBase, forKey: .lensAPIBase)
        try container.encode(c.lensModel, forKey: .lensModel)
    }

    mutating func syncLegacyMirrors() {
        selectedLLMRunner = Self.normalizeRunner(selectedLLMRunner)
        switch selectedLLMRunner {
        case "local":
            lensProvider = "openai"
            lensAPIBase = localBaseURL
            lensModel = localModel
        case "remote":
            lensProvider = "openai"
            lensAPIBase = remoteBaseURL
            lensModel = remoteModel
        default:
            lensProvider = "codex"
            lensAPIBase = remoteBaseURL
            lensModel = remoteModel
        }
    }

    var runnerKind: LLMRunnerKind {
        LLMRunnerKind(rawValue: Self.normalizeRunner(selectedLLMRunner)) ?? .local
    }

    static func normalizeRunner(_ raw: String) -> String {
        switch raw.lowercased() {
        case "codex": return "codex"
        case "local": return "local"
        case "remote", "remotecompatible", "ollamacloud", "openai": return "remote"
        default: return "local"
        }
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Paths.configURL) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save() throws {
        try Paths.ensureAppSupport()
        var copy = self
        copy.syncLegacyMirrors()
        let data = try JSONEncoder().encode(copy)
        try data.write(to: Paths.configURL, options: [.atomic])
    }
}

enum LLMRunnerKind: String, Codable, CaseIterable, Sendable {
    case codex
    case local
    case remote

    var label: String {
        switch self {
        case .codex: return "Codex CLI"
        case .local: return "Local (Ollama / LM Studio)"
        case .remote: return "Remote (OpenAI-compatible)"
        }
    }

    var isB1: Bool {
        switch self {
        case .local: return false
        case .codex, .remote: return true
        }
    }
}
