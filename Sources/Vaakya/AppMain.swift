import AppKit
import SwiftUI
import VaakyaCore

/// Vaakya is a Dock-visible app with menu-bar dictation and a main Transcripts window.
///
/// Utility panels still open via `WindowManager` (AppKit) so menu-bar actions stay reliable.
@main
struct VaakyaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(Self.requireEnvironment())
                .tint(YapTheme.coral)
        } label: {
            Image(systemName: "waveform.circle")
        }
        .menuBarExtraStyle(.menu)
    }

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
        // Regular app → Dock icon + task switcher. Menu bar extra remains available.
        NSApp.setActivationPolicy(.regular)
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
        environment.transcriptionRunner.resumePendingJobs()
        if environment.needsOnboarding {
            WindowManager.shared.open("onboarding")
        } else {
            WindowManager.shared.openMain()
            Task { @MainActor in
                await environment.coordinator.prepareModels()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock click / Cmd-Tab when windows are hidden.
        if !flag {
            if AppEnvironment.startup.environment?.needsOnboarding == true {
                WindowManager.shared.open("onboarding")
            } else {
                WindowManager.shared.openMain()
            }
        } else {
            WindowManager.shared.focusMainOrOpen()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep menu-bar dictation alive when the main window is closed.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.startup.environment?.askService.cancelAllInFlight()
        CodexLensClient.cancelAll()
        AppEnvironment.startup.environment?.meetingCapture.abortForTermination()
        AppEnvironment.startup.environment?.coordinator.stop()
    }
}
