import AppKit
import SwiftUI

/// Opens the app's panels as plain NSWindows (AppKit-managed).
///
/// Menu-bar content cannot reliably use `@Environment(\.openWindow)` — opening
/// NSWindows directly from menu actions is deterministic.
///
/// Primary workspace is the YapYap-inspired `MainShellView` (single window navigation).
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

    private init() {}

    /// Primary workspace window (Dock / Cmd-Tab destination).
    func openMain() {
        openShell(route: nil)
    }

    func focusMainOrOpen() {
        if let existing = windows["main"] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openMain()
        }
    }

    /// Show shell and optionally jump to a destination.
    func openShell(route: ShellRouter.Destination?) {
        if let route {
            ShellRouter.shared.go(route)
        }
        if let existing = windows["main"] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment = AppEnvironment.startup.environment else { return }
        let root = MainShellView()
            .environment(environment)
            .tint(YapTheme.coral)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Vaakya"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.setFrameAutosaveName("Vaakya.main")
        window.center()
        windows["main"] = window
        // Keep legacy id alias so older call sites still find the window.
        windows["transcripts"] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Show (or create) the window for the given panel id.
    /// Panel ids: "history", "dictionary", "settings", "onboarding", "transcripts".
    func open(_ id: String) {
        switch id {
        case "transcripts", "main":
            openShell(route: .home)
        case "settings":
            openShell(route: .settings)
        case "dictionary":
            openShell(route: .dictionary)
        case "history":
            openShell(route: .history)
        case "onboarding":
            openStandalone(id: "onboarding")
        default:
            break
        }
    }

    func close(_ id: String) {
        if id == "transcripts" || id == "main" {
            windows["main"]?.close()
            windows["main"] = nil
            windows["transcripts"] = nil
            return
        }
        windows[id]?.close()
        windows[id] = nil
    }

    // MARK: - standalone (onboarding only)

    private func openStandalone(id: String) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment = AppEnvironment.startup.environment else { return }
        let content = OnboardingView().environment(environment).tint(YapTheme.coral)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Vaakya — Get Started"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 600))
        window.setFrameAutosaveName("Vaakya.onboarding")
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
