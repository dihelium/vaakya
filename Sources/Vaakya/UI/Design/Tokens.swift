import AppKit
import SwiftUI

/// Macro layout tokens — tuned for YapYap-like air and quiet density.
enum VaakyaSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let hero: CGFloat = 48

    /// Outer window padding (generous, product-marketing grade).
    static let panelInset: CGFloat = 28
    /// Vertical gap between major blocks.
    static let section: CGFloat = 28
    /// Comfortable list-row vertical padding.
    static let rowY: CGFloat = 14
}

enum VaakyaRadius {
    static let card: CGFloat = 14
    static let row: CGFloat = 12
    static let badge: CGFloat = 8
    static let pill: CGFloat = 999
}

/// Soft surfaces inspired by warm product UIs; still system-adaptive in dark mode.
enum VaakyaSurface {
    /// Main canvas — warm off-white in light, system window in dark.
    static var canvas: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return .windowBackgroundColor
            }
            return NSColor(srgbRed: 0.965, green: 0.953, blue: 0.937, alpha: 1) // ~#F6F3EF
        })
    }

    /// Raised card / selected row.
    static var card: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return .controlBackgroundColor
            }
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
        })
    }

    /// Subtle recessed sidebar strip.
    static var sidebar: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor.controlBackgroundColor.withAlphaComponent(0.55)
            }
            return NSColor(srgbRed: 0.945, green: 0.932, blue: 0.915, alpha: 1)
        })
    }

    /// Soft hairline for borders.
    static var hairline: Color {
        Color.primary.opacity(0.08)
    }
}
