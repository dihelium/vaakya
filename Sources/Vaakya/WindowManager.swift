import AppKit
import SwiftUI

/// Opens the app's utility panels as plain NSWindows (AppKit-managed).
///
/// Menu-bar content cannot reliably use `@Environment(\.openWindow)` — the
/// reported "buttons do nothing" bug (user feedback 2026-08-02). Opening
/// NSWindows directly from menu actions is deterministic and avoids the
/// SwiftUI scene/WindowGroup dependency entirely.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var windows: [String: NSWindow] = [:]

    private init() {}

    /// Show (or create) the window for the given panel id.
    /// Panel ids: "history", "dictionary", "settings", "onboarding".
    func open(_ id: String) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment = AppEnvironment.startup.environment,
              let content = content(for: id, environment: environment) else { return }

        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title(for: id)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Vaakya.\(id)")
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(_ id: String) {
        windows[id]?.close()
        windows[id] = nil
    }

    // MARK: - internals

    private func content(for id: String, environment: AppEnvironment) -> AnyView? {
        switch id {
        case "history": return AnyView(HistoryView().environment(environment))
        case "dictionary": return AnyView(DictionaryView().environment(environment))
        case "settings": return AnyView(SettingsView().environment(environment))
        case "onboarding": return AnyView(OnboardingView().environment(environment))
        default: return nil
        }
    }

    private func title(for id: String) -> String {
        switch id {
        case "history": return "Vaakya History"
        case "dictionary": return "Vaakya Dictionary"
        case "settings": return "Vaakya Settings"
        case "onboarding": return "Vaakya — Get Started"
        default: return "Vaakya"
        }
    }
}
