import AppKit
import AVFoundation
import Security
import SwiftUI
import VaakyaCore

/// Onboarding: permission checks (mic / accessibility / input monitoring) with
/// deep links, model-consent (states exactly what downloads, plan 1.4), and the
/// privacy details for the optional model-backed cleanup pass.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axGranted = AXIsProcessTrusted()
    @State private var inputGranted = CGPreflightListenEventAccess()
    @State private var isPreparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vaakya — get started").font(.title2.bold())

            PermissionRow(title: "Microphone",
                          detail: "Used only to capture your dictation. Audio never leaves this Mac.",
                          granted: micGranted,
                          settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                MicRecorder.requestMicPermission { granted in
                    Task { @MainActor in micGranted = granted }
                }
            }

            PermissionRow(title: "Accessibility",
                          detail: "Types text at your cursor and learns from your edits.",
                          granted: axGranted,
                          settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { axGranted = AXIsProcessTrusted() }
            }

            PermissionRow(title: "Input Monitoring",
                          detail: "Lets the hotkey (hold Left Option) be seen by Vaakya.",
                          granted: inputGranted,
                          settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                _ = CGRequestListenEventAccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { inputGranted = CGPreflightListenEventAccess() }
            }

            Divider()

            // Model consent (plan 1.4): one-time ~450 MB Parakeet download from Hugging Face.
            VStack(alignment: .leading, spacing: 6) {
                Text("Speech model (one-time download)").font(.headline)
                Text("On first use, Vaakya downloads the Parakeet TDT 0.6B v2 CoreML model "
                     + "(~450 MB) from Hugging Face via FluidAudio. After it is cached, the app "
                     + "works fully offline — nothing else ever leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Optional: an on-device LLM cleanup pass (Stage 2) can be enabled in Settings. "
                     + "Note it may use Apple's Foundation Models, which can route through Apple's "
                     + "Private Cloud Compute — it is OFF until you opt in.")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button(isPreparing ? "Preparing…" : (env.coordinator.state.modelsReady ? "Models ready ✓" : "Download & prepare models")) {
                        Task {
                            isPreparing = true
                            await env.prepareModelsWithConsent()
                            isPreparing = false
                        }
                    }
                    .disabled(isPreparing || env.coordinator.state.modelsReady)
                    Button("Skip for now") { env.needsOnboarding = false }
                        .disabled(isPreparing)
                }
            }

            Divider()

            // Diagnostics: helps debug TCC registration (e.g. mic missing from
            // System Settings) — shows what macOS sees for this app.
            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnostics").font(.headline)
                Text("Bundle: \(Bundle.main.bundleIdentifier ?? "?") · v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Signature: \(Self.signingIdentity()) · Team ID: \(Self.teamIdentifier() ?? "none")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Microphone status: \(MicRecorder.micStatus == .granted ? "granted" : MicRecorder.micStatus == .denied ? "denied" : "not asked yet")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("If the mic prompt never appears, verify the hardened-runtime audio-input entitlement in the app's code signature.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let settingsURL: String
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").font(.caption).foregroundStyle(.green)
            } else {
                Button("Grant", action: request)
                Button("Settings", action: {
                    if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
                })
            }
        }
    }
}

private extension OnboardingView {
    /// Signing identity as seen by the code-signing API — the key diagnostic
    /// for TCC not registering the app (self-signed ⇒ Team ID "none").
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
