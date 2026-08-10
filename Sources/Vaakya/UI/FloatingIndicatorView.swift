import AppKit
import SwiftUI

/// Floating recording indicator: always-on-top pill while recording or transcribing.
@MainActor
final class FloatingIndicator {
    static let shared = FloatingIndicator()
    private static let indicatorSize = NSSize(width: 200, height: 48)

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
        } else if let hosting = window?.contentViewController as? NSHostingController<FloatingIndicatorView> {
            hosting.rootView = FloatingIndicatorView(state: state)
        }
        positionNearCursor()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionNearCursor() {
        let mouse = NSEvent.mouseLocation
        guard let window, let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = Self.indicatorSize
        window.setContentSize(size)
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y + 24)
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        window.setFrameOrigin(origin)
    }
}

private struct FloatingIndicatorView: View {
    let state: AppState

    private var isRecording: Bool { state.phase == .recording }

    var body: some View {
        HStack(spacing: VaakyaSpace.sm) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red.opacity(0.2) : Color.accentColor.opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: isRecording ? "record.circle.fill" : "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRecording ? YapTheme.coral : Color.secondary)
                    .symbolEffect(.pulse, isActive: isRecording && !reduceMotion)
            }
            Text(isRecording ? "Recording" : "Transcribing")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(YapTheme.coral.opacity(isRecording ? 0.35 : 0.12)))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRecording ? "Recording" : "Transcribing")
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
