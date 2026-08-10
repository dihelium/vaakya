import AppKit
import Foundation
import SwiftUI

/// Single short click for settings hover, played on the AppKit main actor.
@MainActor
enum HoverSound {
    private static let click = makeClick()

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
        click?.play()
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
