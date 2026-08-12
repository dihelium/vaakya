import Foundation

/// The single ASR spine for dictation, meeting capture, and imported audio.
///
/// Vaakya keeps one Parakeet profile so Hindi + romanized Hinglish + English
/// conversations are transcribed by the same model whether the user holds the
/// hotkey or presses start recording.
public struct SpeechRecognitionProfile: Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// FluidAudio `AsrModelVersion` name (`v2`, `v3`, …). The app target maps this.
    public let fluidAudioVersionName: String
    public let summary: String

    public init(id: String,
                displayName: String,
                fluidAudioVersionName: String,
                summary: String) {
        self.id = id
        self.displayName = displayName
        self.fluidAudioVersionName = fluidAudioVersionName
        self.summary = summary
    }

    /// Parakeet TDT 0.6B v2 — English + romanized Hinglish. This is the
    /// verified dictation model and the only meeting/import ASR.
    public static let parakeetTDTv2 = SpeechRecognitionProfile(
        id: "parakeet-tdt-0.6b-v2",
        displayName: "Parakeet TDT v2",
        fluidAudioVersionName: "v2",
        summary: "Same local Parakeet model for dictation, meetings, and imported audio. Handles English and romanized Hindi together."
    )

    public static let shared = parakeetTDTv2
    public static let dictation = shared
    public static let meeting = shared
    public static let importedAudio = shared

    public static func displayName(for modelID: String) -> String {
        if modelID == parakeetTDTv2.id { return parakeetTDTv2.displayName }
        return modelID
    }
}
