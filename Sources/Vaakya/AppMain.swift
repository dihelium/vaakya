import AppKit
import SwiftUI
import VaakyaCore

/// Vaakya is a private, personalized menu-bar dictation app.
///
/// The menu bar is the single scene; all utility panels (History, Dictionary,
/// Settings, Onboarding) open as AppKit windows via `WindowManager` — the
/// SwiftUI `openWindow` route from MenuBarExtra content was unreliable
/// (user feedback 2026-08-02: buttons did nothing).
@main
struct VaakyaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(Self.requireEnvironment())
        } label: {
            Image(systemName: "waveform.circle")
        }
        .menuBarExtraStyle(.menu)
    }

    /// Startup failure is unrecoverable (data dir unwritable / DB corrupt):
    /// fail loudly with the cause rather than running half-broken.
    private static func requireEnvironment() -> AppEnvironment {
        guard let env = AppEnvironment.startup.environment else {
            fatalError("Vaakya couldn't start: \(AppEnvironment.startup.error?.localizedDescription ?? "unknown error")")
        }
        return env
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let error = AppEnvironment.startup.error {
            let alert = NSAlert()
            alert.messageText = "Vaakya couldn't start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        guard let environment = AppEnvironment.startup.environment else { return }
        environment.coordinator.start()
        if environment.needsOnboarding {
            WindowManager.shared.open("onboarding")
        } else {
            // Consent was persisted on a prior launch. Preparing here loads
            // FluidAudio's cached models. It adds no network path to Vaakya.
            Task { @MainActor in
                await environment.coordinator.prepareModels()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.startup.environment?.coordinator.stop()
    }
}
