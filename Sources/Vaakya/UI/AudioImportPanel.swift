import AppKit
import UniformTypeIdentifiers

@MainActor
enum AudioImportPanel {
    static func chooseAndEnqueue(in environment: AppEnvironment) {
        if !environment.config.diarizationModelConsentGiven {
            let consent = NSAlert()
            consent.messageText = "Download speaker diarization models?"
            consent.informativeText = "Vaakya needs a separate one-time FluidAudio model download to identify speakers. Audio and transcripts remain on this Mac."
            consent.addButton(withTitle: "Allow and Continue")
            consent.addButton(withTitle: "Cancel")
            guard consent.runModal() == .alertFirstButtonReturn else { return }
            environment.grantDiarizationConsent()
            guard environment.config.diarizationModelConsentGiven else { return }
        }
        let panel = NSOpenPanel()
        panel.title = "Transcribe Audio"
        panel.message = "Choose an iPhone Voice Memo or another audio file. Vaakya keeps a private managed copy."
        panel.prompt = "Transcribe"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["m4a", "wav", "caf", "aiff", "aif"]
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        environment.transcriptionRunner.enqueue(url: url, securityScoped: accessed)
        WindowManager.shared.open("transcripts")
    }
}
