import AppKit
import SwiftUI

@main
struct VaakyaWorkSafeApp: App {
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

    private static func requireEnvironment() -> AppEnvironment {
        guard let environment = AppEnvironment.startup.environment else {
            fatalError("Vaakya could not start: \(AppEnvironment.startup.error?.localizedDescription ?? "unknown error")")
        }
        return environment
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let error = AppEnvironment.startup.error {
            let alert = NSAlert()
            alert.messageText = "Vaakya could not start"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        guard let environment = AppEnvironment.startup.environment else { return }
        environment.coordinator.start()
        if environment.needsOnboarding {
            WindowManager.shared.openOnboarding()
        } else {
            WindowManager.shared.openMain()
            Task { await environment.coordinator.prepareModels() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppEnvironment.startup.environment?.needsOnboarding == true {
            WindowManager.shared.openOnboarding()
        } else {
            WindowManager.shared.openMain()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.startup.environment?.coordinator.stop()
    }
}
