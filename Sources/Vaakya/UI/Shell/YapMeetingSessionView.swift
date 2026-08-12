import SwiftUI
import VaakyaCore

/// Focused recording stage. Capture starts from home's "start recording" CTA.
struct YapMeetingSessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared
    @State private var requestedStart = false

    private var controller: MeetingCaptureController { env.meetingCapture }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 36)
            stage
                .frame(maxWidth: 720)
            Spacer(minLength: 36)
            footer
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .background(YapTheme.canvas)
        .task {
            guard !requestedStart, controller.phase == .idle else { return }
            requestedStart = true
            await controller.start()
        }
        .onChange(of: controller.completedJobID) { _, jobID in
            guard let jobID else { return }
            // Replace Meeting so Esc from Job cannot return into a new capture.
            router.replace(.job(jobID))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            YapBreadcrumb(crumbs: [
                ("vaakya", { backToHome() }),
                ("recording", nil),
            ])
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(headerStatus)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.primary.opacity(0.42))
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch controller.phase {
        case .recording:
            recordingStage
        case .requestingPermissions:
            waitingStage(
                title: "one private permission check",
                message: "Vaakya needs your microphone and Screen & System Audio Recording so it can hear both sides. Audio stays on this Mac."
            )
        case .starting:
            waitingStage(
                title: "opening a listening room",
                message: "Connecting your microphone and Mac audio. Nothing is transcribed until you stop."
            )
        case .stopping:
            waitingStage(
                title: "saving your recording",
                message: "Closing both audio streams, then adding this meeting to your recordings."
            )
        case .failed:
            failureStage
        case .idle:
            waitingStage(
                title: "ready to listen",
                message: "Vaakya will capture you and the people speaking through your Mac."
            )
        }
    }

    private var recordingStage: some View {
        VStack(spacing: 36) {
            VStack(spacing: 12) {
                Text(controller.isPaused ? "PAUSED" : "LISTENING LOCALLY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(YapTheme.coral)
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(elapsedText(at: context.date))
                        .font(.system(size: 80, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .tracking(-2.5)
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .contentTransition(.numericText())
                }
                Text(controller.isPaused
                     ? "tap play to keep listening"
                     : "same \(SpeechRecognitionProfile.shared.displayName) model as dictation · audio stays here")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary.opacity(0.42))
            }

            VStack(spacing: 18) {
                sourceMeter(title: "your microphone", systemImage: "mic.fill",
                            level: controller.microphoneLevel)
                sourceMeter(title: "Mac and call audio", systemImage: "speaker.wave.2.fill",
                            level: controller.systemLevel)
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )

            HStack(spacing: 14) {
                YapPillButton(
                    title: controller.isPaused ? "play" : "pause",
                    systemImage: controller.isPaused ? "play.fill" : "pause.fill",
                    filled: false
                ) {
                    controller.togglePause()
                }
                YapPillButton(title: "stop and save", systemImage: "stop.fill") {
                    Task { await controller.stop() }
                }
            }
        }
    }

    private func waitingStage(title: String, message: String) -> some View {
        VStack(spacing: 22) {
            ProgressView()
                .controlSize(.large)
                .tint(YapTheme.coral)
            Text(title)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .tracking(-0.6)
            Text(message)
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.48))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 540)
        }
    }

    private var failureStage: some View {
        VStack(spacing: 22) {
            Image(systemName: controller.permissionIssue == nil ? "waveform.badge.exclamationmark" : "lock.trianglebadge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(YapTheme.coral)
            Text(controller.permissionIssue == nil ? "recording stopped" : "Vaakya needs your okay")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .tracking(-0.6)
            Text(controller.lastError ?? "Recording could not continue.")
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.52))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 580)

            HStack(spacing: 12) {
                if controller.permissionIssue != nil {
                    YapPillButton(title: "open System Settings", systemImage: "gearshape.fill", filled: false) {
                        controller.openPermissionSettings()
                    }
                }
                if controller.recoveryDirectory != nil {
                    YapPillButton(title: "save recovered audio", systemImage: "square.and.arrow.down") {
                        Task { await controller.saveRecoveredCapture() }
                    }
                }
                YapPillButton(title: "try again", systemImage: "arrow.clockwise") {
                    requestedStart = false
                    Task {
                        await controller.start()
                        requestedStart = true
                    }
                }
            }
            .padding(.top, 4)

            YapTextLink(title: "back to home") {
                backToHome()
            }
        }
    }

    private func sourceMeter(title: String, systemImage: String, level: Float) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YapTheme.coral)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 148, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(YapTheme.coral.opacity(controller.isPaused ? 0.35 : 0.88))
                        .frame(width: max(5, geometry.size.width * normalizedLevel(level)))
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(height: 10)
            Text(controller.isPaused ? "paused" : (level > 0.002 ? "hearing" : "quiet"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var footer: some View {
        HStack {
            Text("Hold-Option dictation pauses while this room is listening.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.34))
            Spacer()
            if controller.phase == .failed || controller.phase == .idle {
                YapTextLink(title: "cancel") { backToHome() }
            }
        }
    }

    private var headerStatus: String {
        switch controller.phase {
        case .idle: return "READY"
        case .requestingPermissions: return "PERMISSIONS"
        case .starting: return "CONNECTING"
        case .recording: return controller.isPaused ? "PAUSED" : "LISTENING"
        case .stopping: return "SAVING"
        case .failed: return "NEEDS ATTENTION"
        }
    }

    private var statusDotColor: Color {
        if controller.phase == .recording {
            return controller.isPaused ? Color.primary.opacity(0.35) : YapTheme.coral
        }
        return Color.primary.opacity(0.22)
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = controller.elapsedSeconds(at: date)
        if seconds >= 3600 {
            return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func normalizedLevel(_ level: Float) -> CGFloat {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(max(level, 0.0001))
        return CGFloat(min(1, max(0.03, (decibels + 55) / 55)))
    }

    private func backToHome() {
        guard controller.phase != .recording && controller.phase != .stopping else { return }
        controller.reset()
        router.popToRoot()
    }

    /// Shared guard for Esc / shell back while capture is live.
    var blocksNavigation: Bool {
        controller.phase == .recording || controller.phase == .stopping
            || controller.phase == .starting || controller.phase == .requestingPermissions
    }
}
