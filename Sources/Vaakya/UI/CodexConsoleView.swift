import AppKit
import SwiftUI

/// Read-only terminal-style viewer for live Codex CLI output.
struct CodexConsoleView: View {
    @Bindable var store: CodexConsoleStore
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(VaakyaSpace.md)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.65))
                .onChange(of: store.lines.count) { _, count in
                    if count > 0 {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
        .background(VaakyaSurface.canvas)
    }

    private var header: some View {
        HStack(spacing: VaakyaSpace.md) {
            Image(systemName: "terminal.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.title)
                    .font(.headline)
                Text(store.isRunning
                     ? "Running — output is read-only"
                     : "Session log kept until you dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRunning {
                ProgressView().controlSize(.small)
                Badge(title: "Live", systemImage: "dot.radiowaves.left.and.right", tone: .info)
            } else if !store.lines.isEmpty {
                Badge(title: "Idle", tone: .neutral)
            }
            Button("Copy all") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.fullText, forType: .string)
            }
            .disabled(store.lines.isEmpty)
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, VaakyaSpace.lg)
        .padding(.vertical, VaakyaSpace.md)
    }

    private var footer: some View {
        Text("Log of the `codex exec` process Vaakya launched. You cannot type into it. Closing keeps the process running.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(VaakyaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("—") || line.hasPrefix("$") {
            return .secondary
        }
        if line.localizedCaseInsensitiveContains("error")
            || line.localizedCaseInsensitiveContains("failed") {
            return SemanticTone.danger.color.opacity(0.95)
        }
        return .primary
    }
}
