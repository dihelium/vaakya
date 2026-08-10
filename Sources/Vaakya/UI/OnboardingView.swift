import AppKit
import AVFoundation
import Security
import SwiftUI
import VaakyaCore

/// First-run: permissions, speech model consent, and TCC diagnostics.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var inputGranted = CGPreflightListenEventAccess()
    @State private var isPreparing = false
    @State private var prepareError: String?

    private var allPermissionsGranted: Bool { micGranted && axGranted && inputGranted }
    private var modelsReady: Bool { env.coordinator.state.modelsReady }
    private var isReady: Bool { allPermissionsGranted && modelsReady }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Welcome to Vaakya",
                subtitle: "private voice on this Mac — grant permissions, then download the speech model once"
            )
            Rectangle().fill(VaakyaSurface.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: VaakyaSpace.section) {
                    if isReady {
                        readyCard
                    }

                    permissionsSection
                    modelSection

                    DisclosureGroup("Diagnostics") {
                        diagnosticsBody
                            .padding(.top, VaakyaSpace.sm)
                    }
                    .font(.subheadline.weight(.medium))

                    if !isReady {
                        HStack {
                            Spacer()
                            Button("Continue without models") {
                                env.needsOnboarding = false
                                WindowManager.shared.close("onboarding")
                                WindowManager.shared.openMain()
                            }
                            .disabled(isPreparing)
                        }
                    } else {
                        HStack {
                            Spacer()
                            Button("Open Vaakya") {
                                env.needsOnboarding = false
                                WindowManager.shared.close("onboarding")
                                WindowManager.shared.openMain()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                }
                .padding(VaakyaSpace.panelInset)
            }
        }
        .frame(minWidth: 560, minHeight: 580)
        .background(VaakyaSurface.canvas)
        .tint(YapTheme.coral)
        .onAppear { refreshPermissions() }
    }

    // MARK: - Sections

    private var readyCard: some View {
        HStack(spacing: VaakyaSpace.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You’re ready to dictate")
                    .font(.headline)
                Text("Hold Left Option to speak into any app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(VaakyaSpace.xl)
        .background(SemanticTone.success.color.opacity(0.10), in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: VaakyaRadius.card).strokeBorder(VaakyaSurface.hairline, lineWidth: 1))
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.md) {
            Text("Permissions")
                .font(.headline)
            Text("Vaakya needs these to capture speech, type at the cursor, and see the hotkey.")
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionCard(
                title: "Microphone",
                detail: "Captures dictation only. Audio never leaves this Mac.",
                granted: micGranted,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
                request: {
                    MicRecorder.requestMicPermission { granted in
                        Task { @MainActor in micGranted = granted }
                    }
                }
            )

            permissionCard(
                title: "Accessibility",
                detail: "Types text at your cursor and learns from your edits.",
                granted: axGranted,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                request: {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        axGranted = AXIsProcessTrusted()
                    }
                }
            )

            permissionCard(
                title: "Input Monitoring",
                detail: "Lets Vaakya see the hold-Left Option hotkey.",
                granted: inputGranted,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
                request: {
                    _ = CGRequestListenEventAccess()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        inputGranted = CGPreflightListenEventAccess()
                    }
                }
            )

            Button("Re-check permissions") {
                refreshPermissions()
                env.coordinator.refreshPermissions()
            }
            .font(.caption)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: VaakyaSpace.md) {
            Text("Speech model")
                .font(.headline)
            Text("One-time ~450 MB download of Parakeet TDT 0.6B v2 (Core ML) from Hugging Face via FluidAudio. After that, recognition works fully offline.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Optional Stage 2 cleanup (Settings) may use Apple Foundation Models / Private Cloud Compute — off until you enable it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: VaakyaSpace.sm) {
                if modelsReady {
                    Badge(title: "Models ready", systemImage: "checkmark.circle.fill", tone: .success)
                } else if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Download & prepare models") {
                        Task {
                            isPreparing = true
                            prepareError = nil
                            await env.prepareModelsWithConsent()
                            isPreparing = false
                            if !env.coordinator.state.modelsReady {
                                prepareError = env.coordinator.state.lastError
                                    ?? "Model preparation didn’t finish. You can retry."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing)
                }
            }

            if let prepareError {
                FeedbackMessage(text: prepareError, tone: .danger)
            }
        }
        .padding(VaakyaSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaakyaSurface.card, in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: VaakyaRadius.card).strokeBorder(VaakyaSurface.hairline, lineWidth: 1))
    }

    private var diagnosticsBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bundle: \(Bundle.main.bundleIdentifier ?? "?") · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
            Text("Signature: \(Self.signingIdentity()) · Team ID: \(Self.teamIdentifier() ?? "none")")
            Text("Microphone status: \(MicRecorder.micStatus == .granted ? "granted" : MicRecorder.micStatus == .denied ? "denied" : "not asked yet")")
            Text("If the mic prompt never appears, verify the audio-input entitlement on a properly signed build.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private func permissionCard(
        title: String,
        detail: String,
        granted: Bool,
        settingsURL: String,
        request: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: VaakyaSpace.md) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(granted ? SemanticTone.success.color : Color.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.body.weight(.semibold))
                    if granted {
                        Badge(title: "Granted", tone: .success)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VaakyaSpace.sm)

            if !granted {
                HStack(spacing: VaakyaSpace.sm) {
                    Button("Grant", action: request)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Settings") {
                        if let url = URL(string: settingsURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(VaakyaSpace.xl)
        .background(VaakyaSurface.card, in: RoundedRectangle(cornerRadius: VaakyaRadius.card))
        .overlay(RoundedRectangle(cornerRadius: VaakyaRadius.card).strokeBorder(VaakyaSurface.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
        inputGranted = CGPreflightListenEventAccess()
    }
}

private extension OnboardingView {
    static func signingIdentity() -> String {
        let url = Bundle.main.bundleURL as CFURL
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(), &code) == errSecSuccess, let code else {
            return "unsigned"
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any],
              let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let cert = certs.first else { return "unsigned" }
        return (SecCertificateCopySubjectSummary(cert) as String?) ?? "unknown"
    }

    static func teamIdentifier() -> String? {
        let url = Bundle.main.bundleURL as CFURL
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url, SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
