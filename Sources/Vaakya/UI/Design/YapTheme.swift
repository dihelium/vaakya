import AppKit
import SwiftUI

/// Visual language heavily inspired by YapYap Studio’s public UI
/// (warm canvas, coral accent, airy type, soft pills, hover motion).
enum YapTheme {
    /// Coral / terracotta primary action color.
    static let coral = Color(red: 0.890, green: 0.420, blue: 0.365) // ~#E36B5D
    static let coralHot = Color(red: 0.95, green: 0.32, blue: 0.28) // hover ring
    static let coralSoft = Color(red: 0.890, green: 0.420, blue: 0.365).opacity(0.14)
    static let orbOuter = Color(red: 0.22, green: 0.14, blue: 0.12)
    static let muted = Color.primary.opacity(0.45)

    static var canvas: Color { VaakyaSurface.canvas }
    static var card: Color { VaakyaSurface.card }
    static var sidebar: Color { VaakyaSurface.sidebar }
    static var hairline: Color { VaakyaSurface.hairline }

    static func wordmark(_ title: String = "vaakya") -> some View {
        Text(title)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .tracking(-0.6)
            .foregroundStyle(Color.primary.opacity(0.92))
    }

    static func whisper(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.42))
    }

    static func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Color.primary.opacity(0.38))
    }
}

// MARK: - Interactive primitives

/// Large coral pill with hover scale + brightness.
struct YapPillButton: View {
    let title: String
    var systemImage: String? = nil
    var filled: Bool = true
    var compact: Bool = false
    /// YapYap-scale hero CTA (home primary action).
    var large: Bool = false
    let action: () -> Void

    @State private var hovering = false

    private var fontSize: CGFloat {
        if large { return 22 }
        if compact { return 14 }
        return 17
    }

    private var hPad: CGFloat {
        if large { return 44 }
        if compact { return 18 }
        return 28
    }

    private var vPad: CGFloat {
        if large { return 20 }
        if compact { return 10 }
        return 14
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 8 : large ? 12 : 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: large ? 18 : compact ? 13 : 15, weight: .semibold))
                } else if filled {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: large ? 10 : compact ? 7 : 8,
                               height: large ? 10 : compact ? 7 : 8)
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? YapTheme.coral : Color.primary.opacity(hovering ? 0.10 : 0.06))
            )
            .foregroundStyle(filled ? Color.white : Color.primary)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(filled ? 0.14 : 0.10), lineWidth: 1)
                    .offset(y: filled ? 1.5 : 0)
            )
            .shadow(color: Color.black.opacity(filled && hovering ? 0.20 : filled ? 0.12 : 0),
                    radius: hovering ? 12 : large ? 6 : 0, x: 0, y: hovering ? 5 : large ? 3 : 2)
            .scaleEffect(hovering ? 1.04 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovering)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}

/// Floating orb: dark ring + coral face; coral ring lights up on hover (YapYap energy).
struct YapOrbButton: View {
    var helpText: String = "Settings"
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer dark disc
                Circle()
                    .fill(YapTheme.orbOuter)
                    .frame(width: 48, height: 48)
                // Hover / idle ring
                Circle()
                    .strokeBorder(
                        hovering ? YapTheme.coralHot : Color.primary.opacity(0.22),
                        lineWidth: hovering ? 2.5 : 1.5
                    )
                    .frame(width: 48, height: 48)
                // Coral face with eyes
                Circle()
                    .fill(YapTheme.coral)
                    .frame(width: 26, height: 26)
                    .overlay {
                        HStack(spacing: 5) {
                            Circle().fill(Color.white.opacity(0.95)).frame(width: 4, height: 4)
                            Circle().fill(Color.white.opacity(0.95)).frame(width: 4, height: 4)
                        }
                        .offset(y: -1)
                    }
                    .scaleEffect(hovering ? 1.06 : 1.0)
            }
            .shadow(color: YapTheme.coral.opacity(hovering ? 0.45 : 0.15),
                    radius: hovering ? 12 : 4, y: hovering ? 2 : 1)
            .scaleEffect(hovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: hovering)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

/// Quiet text link that brightens + underlines on hover.
struct YapTextLink: View {
    let title: String
    var underlined: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(hovering ? 0.72 : 0.38))
                .underline(underlined || hovering, color: Color.primary.opacity(hovering ? 0.35 : 0.18))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Breadcrumb: vaakya › recordings › name — first crumb is wordmark-scale when linked home.
struct YapBreadcrumb: View {
    let crumbs: [(String, (() -> Void)?)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›")
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .font(.system(size: 16, weight: .medium))
                }
                crumbView(index: index, title: crumb.0, action: crumb.1)
            }
        }
    }

    @ViewBuilder
    private func crumbView(index: Int, title: String, action: (() -> Void)?) -> some View {
        let isFirst = index == 0
        let isLast = index == crumbs.count - 1
        if let action {
            Button(action: action) {
                Text(title)
                    .font(.system(size: isFirst ? 22 : 15,
                                  weight: isFirst ? .semibold : .medium,
                                  design: isFirst ? .rounded : .default))
                    .foregroundStyle(Color.primary.opacity(isFirst ? 0.88 : 0.45))
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .font(.system(size: isLast ? 16 : 15,
                              weight: isLast ? .semibold : .regular,
                              design: isFirst ? .rounded : .default))
                .foregroundStyle(isLast
                                 ? Color.primary.opacity(0.9)
                                 : Color.primary.opacity(0.45))
                .lineLimit(1)
        }
    }
}

/// Soft rounded chip control (status / cancel) with hover.
struct YapChipButton: View {
    let systemImage: String
    var tint: Color = YapTheme.coral
    var destructive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(destructive ? Color.secondary : Color.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(destructive
                              ? Color.primary.opacity(hovering ? 0.12 : 0.08)
                              : tint.opacity(hovering ? 0.95 : 0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
    }
}

/// Rail / list hover fill.
struct YapHoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = 10
    var selected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(selected
                          ? Color.primary.opacity(0.10)
                          : Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func yapHoverHighlight(cornerRadius: CGFloat = 10, selected: Bool = false) -> some View {
        modifier(YapHoverHighlight(cornerRadius: cornerRadius, selected: selected))
    }
}
