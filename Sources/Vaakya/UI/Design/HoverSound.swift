import AppKit
import Foundation
import SwiftUI

/// Single short click for settings hover — fires on every hover enter.
enum HoverSound {
    private final class Retainer: @unchecked Sendable {
        private let lock = NSLock()
        private var live: [NSSound] = []

        func play(_ sound: NSSound) {
            lock.lock()
            live.append(sound)
            // Cap retained sounds to avoid unbounded growth.
            if live.count > 8 {
                live.removeFirst(live.count - 8)
            }
            lock.unlock()
            sound.play()
            // Drop after a short delay (Tink is < 1s).
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.lock.lock()
                self?.live.removeAll { $0 === sound }
                self?.lock.unlock()
            }
        }
    }

    private static let retainer = Retainer()

    private static func makeClick() -> NSSound? {
        let path = "/System/Library/Sounds/Tink.aiff"
        if let s = NSSound(contentsOfFile: path, byReference: false) {
            s.volume = 0.4
            return s
        }
        if let s = NSSound(contentsOfFile: "/System/Library/Sounds/Pop.aiff", byReference: false) {
            s.volume = 0.4
            return s
        }
        return nil
    }

    static func playClick() {
        guard let sound = makeClick() else { return }
        retainer.play(sound)
    }

    static func playSoftDrum() { playClick() }
}

/// Plays one click when the pointer enters this view.
struct YapHoverClick: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering && !hovering {
                    HoverSound.playClick()
                }
                hovering = isHovering
            }
    }
}

extension View {
    func yapHoverClick() -> some View {
        modifier(YapHoverClick())
    }
}
