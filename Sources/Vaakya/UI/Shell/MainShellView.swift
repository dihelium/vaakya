import AppKit
import SwiftUI
import VaakyaCore

/// YapYap-inspired single workspace: home → recordings → detail, plus library screens.
struct MainShellView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable private var router = ShellRouter.shared

    var body: some View {
        ZStack {
            YapTheme.canvas.ignoresSafeArea()
            content

            // Bottom sheet for Archive Ask (home orb / router.openAskSheet).
            if router.presentAskSheet {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        env.askService.cancelAllInFlight()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                            router.closeAskSheet()
                        }
                    }
                    .zIndex(40)

                VStack(spacing: 0) {
                    Spacer(minLength: 28)
                    YapAskView()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 28, y: 8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxHeight: .infinity)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .tint(YapTheme.coral)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: router.presentAskSheet)
        .background(EscKeyMonitor {
            handleEscape()
        })
        .onAppear {
            env.transcriptionRunner.refresh()
        }
    }

    private func handleEscape() {
        // Don't steal Escape from native panels / non-key windows.
        guard NSApp.keyWindow != nil else { return }

        if router.presentAskSheet {
            env.askService.cancelAllInFlight()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                router.closeAskSheet()
            }
            return
        }
        // Block leaving an active meeting capture via Esc.
        if router.destination == .meeting,
           env.meetingCapture.phase == .recording
            || env.meetingCapture.phase == .stopping
            || env.meetingCapture.phase == .starting
            || env.meetingCapture.phase == .requestingPermissions {
            return
        }
        _ = router.goBack()
    }

    @ViewBuilder
    private var content: some View {
        switch router.destination {
        case .home:
            YapHomeView()
        case .meeting:
            YapMeetingSessionView()
        case .recordings:
            YapRecordingsView()
        case .job(let id):
            YapJobDetailView(jobID: id)
        case .settings:
            YapSettingsShellView()
        case .dictionary:
            DictionaryView()
        case .history:
            HistoryView()
        case .ask:
            YapAskView()
        }
    }
}

/// Local key monitor for Escape — works even when a text field is not first responder.
private struct EscKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EscKeyView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EscKeyView)?.onEscape = onEscape
    }

    final class EscKeyView: NSView {
        var onEscape: (() -> Void)?
        nonisolated(unsafe) private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if event.keyCode == 53 { // Escape
                        DispatchQueue.main.async {
                            self?.onEscape?()
                        }
                        return nil // consume
                    }
                    return event
                }
            }
            if window == nil {
                removeMonitor()
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
