import Foundation

/// Live, read-only log of a Codex CLI lens run (stdout/stderr + Vaakya status lines).
/// UI binds to this; nothing here accepts shell input.
@MainActor
@Observable
final class CodexConsoleStore {
    private(set) var title: String = "Codex CLI"
    private(set) var isRunning: Bool = false
    private(set) var lines: [String] = []
    private(set) var commandSummary: String = ""
    /// Full transcript for copy / save.
    var fullText: String { lines.joined(separator: "\n") }

    private let maxLines = 8_000

    func begin(title: String, commandSummary: String) {
        self.title = title
        self.commandSummary = commandSummary
        self.isRunning = true
        self.lines = []
        appendSystem("— Codex console (read-only) —")
        appendSystem(commandSummary)
        appendSystem("")
    }

    func append(_ text: String) {
        guard !text.isEmpty else { return }
        // Split multi-line chunks so the UI can scroll line-by-line.
        let parts = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        for part in parts {
            lines.append(part)
        }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func appendSystem(_ text: String) {
        append(text)
    }

    func finish(success: Bool, detail: String? = nil) {
        isRunning = false
        appendSystem("")
        if success {
            appendSystem("— finished successfully —")
        } else {
            appendSystem("— finished with error —")
        }
        if let detail, !detail.isEmpty {
            appendSystem(detail)
        }
    }

    func clear() {
        lines = []
        commandSummary = ""
        isRunning = false
    }
}
