import Foundation
import Observation

/// Single-window navigation for the YapYap-inspired shell.
///
/// Use explicit operations so Back/Esc behave predictably:
/// - `push` — go deeper (Recordings → Job)
/// - `replace` — swap current (Meeting → Job after save)
/// - `popToRoot` — Home as terminal root
/// - `goBack` — pop stack or close Ask sheet
@MainActor
@Observable
final class ShellRouter {
    static let shared = ShellRouter()

    enum Destination: Equatable, Hashable {
        case home
        case meeting
        case recordings
        case job(String)
        case ask
        case settings
        case dictionary
        case history
    }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case listen
        case recognise
        case understand
        case insight
        case lenses
        case dictionary
        case data
        case about

        var id: String { rawValue }

        var label: String {
            switch self {
            case .listen: return "listen"
            case .recognise: return "recognise"
            case .understand: return "understand"
            case .insight: return "insight"
            case .lenses: return "lenses"
            case .dictionary: return "vocabulary"
            case .data: return "data"
            case .about: return "about"
            }
        }

        var group: String {
            switch self {
            case .listen, .recognise, .understand, .insight: return "pipeline"
            case .lenses, .dictionary: return "library"
            case .data, .about: return "app"
            }
        }

        static var pipeline: [SettingsSection] { [.listen, .recognise, .understand, .insight] }
        static var library: [SettingsSection] { [.lenses, .dictionary] }
        static var app: [SettingsSection] { [.data, .about] }
    }

    var destination: Destination = .home
    var settingsSection: SettingsSection = .lenses
    var presentAskSheet = false
    private(set) var backStack: [Destination] = []

    // MARK: - Navigation ops

    /// Deeper navigation (preserves return path).
    func push(_ dest: Destination) {
        guard dest != .ask else {
            openAskSheet()
            return
        }
        presentAskSheet = false
        if dest != destination {
            if backStack.count > 32 {
                backStack.removeFirst(backStack.count - 32)
            }
            backStack.append(destination)
            destination = dest
        }
    }

    /// Swap current screen without growing stack (e.g. Meeting → Job after save).
    func replace(_ dest: Destination) {
        guard dest != .ask else {
            openAskSheet()
            return
        }
        presentAskSheet = false
        destination = dest
    }

    /// Home as root — clears stack.
    func popToRoot() {
        presentAskSheet = false
        backStack.removeAll()
        destination = .home
    }

    /// Legacy alias: prefer push for drill-down, popToRoot for home.
    func go(_ dest: Destination) {
        switch dest {
        case .home:
            popToRoot()
        case .ask:
            openAskSheet()
        case .job, .meeting, .recordings, .settings, .dictionary, .history:
            push(dest)
        }
    }

    @discardableResult
    func goBack() -> Bool {
        if presentAskSheet {
            presentAskSheet = false
            return true
        }
        if let prev = backStack.popLast() {
            destination = prev
            return true
        }
        if destination != .home {
            destination = .home
            return true
        }
        return false
    }

    func openAskSheet() {
        presentAskSheet = true
    }

    func closeAskSheet() {
        presentAskSheet = false
    }

    /// Settings child path: open vocabulary and remember section for return.
    func openVocabularyFromSettings() {
        settingsSection = .dictionary
        push(.dictionary)
    }

    func openPanelID(_ id: String) {
        switch id {
        case "transcripts", "main": popToRoot()
        case "settings": push(.settings)
        case "dictionary": push(.dictionary)
        case "history": push(.history)
        case "ask": openAskSheet()
        default: break
        }
    }
}
