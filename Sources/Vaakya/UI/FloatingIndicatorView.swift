import AppKit
import SwiftUI

/// Floating recording indicator (plan 1.5): a small always-on-top pill shown
/// while recording or transcribing.
@MainActor
final class FloatingIndicator {
    static let shared = FloatingIndicator()
    private static let indicatorSize = NSSize(width: 180, height: 44)

    private var window: NSWindow?

    private init() {}

    func show(state: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: FloatingIndicatorView(state: state))
            let win = NSWindow(contentViewController: hosting)
            win.styleMask = [.borderless, .nonactivatingPanel]
            win.level = .floating
            win.isOpaque = false
            win.backgroundColor = .clear
            win.isMovableByWindowBackground = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window = win
        }
        positionNearCursor()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionNearCursor() {
        let mouse = NSEvent.mouseLocation
        guard let window else { return }
        window.setContentSize(Self.indicatorSize)
        window.setFrameOrigin(NSPoint(x: mouse.x - Self.indicatorSize.width / 2,
                                      y: mouse.y + 24))
    }
}

private struct FloatingIndicatorView: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.phase == .recording ? "record.circle" : "waveform")
                .foregroundStyle(state.phase == .recording ? .red : .secondary)
            Text(state.phase == .recording ? "Recording" : "Transcribing")
                .font(.caption.bold())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
    }
}
