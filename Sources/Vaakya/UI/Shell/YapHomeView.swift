import AVFoundation
import SwiftUI
import VaakyaCore

/// YapYap home: large primary "start recording" stage, Ask orb, preferences gear.
struct YapHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared

    @State private var recordingsHover = false
    @State private var prefsHover = false
    @State private var appear = false

    private var jobCount: Int { env.transcriptionRunner.jobs.count }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 56)
                centerStage
                Spacer(minLength: 56)
                bottomBar
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)

            // Bottom-right: opens Archive Ask (pulls up from bottom).
            YapOrbButton(helpText: "Ask archive") {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    router.openAskSheet()
                }
            }
            .padding(32)
        }
        .background(YapTheme.canvas)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { appear = true }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                YapTheme.wordmark()
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                YapTheme.whisper(statusWhisper)
                    .font(.system(size: 16))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: statusWhisper)
            }
            Spacer()
            HStack(spacing: 14) {
                // Preferences: grey → white on hover (not the coral orb).
                Button {
                    router.settingsSection = .lenses
                    router.go(.settings)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(prefsHover ? Color.primary.opacity(0.92) : Color.primary.opacity(0.38))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(prefsHover ? 0.10 : 0.05))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(prefsHover ? 0.18 : 0.10), lineWidth: 1)
                        )
                        .scaleEffect(prefsHover ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled() // avoid automatic blue keyboard-focus ring on window open
                .yapHoverClick()
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) { prefsHover = hovering }
                }
                .help("Preferences")

                Button {
                    router.go(.recordings)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(jobCount) recording\(jobCount == 1 ? "" : "s")")
                            .font(.system(size: 15, weight: .medium))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.primary.opacity(recordingsHover ? 0.85 : 0.5))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(recordingsHover ? 0.28 : 0.14), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(recordingsHover ? 0.06 : 0))
                            )
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { recordingsHover = $0 }
                .animation(.easeOut(duration: 0.15), value: recordingsHover)
            }
        }
    }

    private var centerStage: some View {
        VStack(spacing: 28) {
            YapPillButton(title: "start recording", systemImage: nil, large: true) {
                router.go(.meeting)
            }

            Text("transcribes with \(SpeechRecognitionProfile.shared.displayName) — same as dictation")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.38))

            HStack(spacing: 22) {
                metaChip(systemImage: "mic.fill", text: deviceMicLabel)
                Text("·")
                    .foregroundStyle(Color.primary.opacity(0.22))
                metaChip(systemImage: "speaker.wave.2.fill", text: "Mac + call audio")
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.primary.opacity(0.48))

            if !env.config.diarizationModelConsentGiven {
                YapTextLink(title: "Allow speaker model download") {
                    env.grantDiarizationConsent()
                }
                .foregroundStyle(YapTheme.coral)
                .padding(.top, 2)
            }
        }
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
    }

    private var bottomBar: some View {
        HStack {
            YapTextLink(title: "history") {
                router.go(.history)
            }
            Spacer()
            YapTextLink(title: "import audio file", underlined: true) {
                AudioImportPanel.chooseAndEnqueue(in: env)
                router.go(.recordings)
            }
            Spacer()
                .frame(minWidth: 80)
        }
        .padding(.trailing, 72)
        .padding(.bottom, 10)
    }

    private var statusWhisper: String {
        if env.meetingCapture.isSessionActive {
            return env.meetingCapture.isPaused ? "recording paused" : "recording a meeting…"
        }
        switch env.coordinator.state.phase {
        case .recording: return "dictating…"
        case .transcribing: return "transcribing…"
        case .idle:
            if !env.coordinator.hotkeyActive {
                return "hotkey inactive — grant Input Monitoring"
            }
            if !env.coordinator.state.modelsReady {
                return "speech model not ready"
            }
            return "ready when you are"
        }
    }

    private var deviceMicLabel: String {
        if let name = AVCaptureDevice.default(for: .audio)?.localizedName, !name.isEmpty {
            return name
        }
        switch MicRecorder.micStatus {
        case .granted: return "Microphone ready"
        case .denied: return "Microphone denied"
        default: return "Microphone not granted"
        }
    }
}
