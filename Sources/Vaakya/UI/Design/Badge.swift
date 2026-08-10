import SwiftUI

/// Compact soft pill — quieter than system chips; used for status/metadata.
struct Badge: View {
    let title: String
    var systemImage: String? = nil
    var tone: SemanticTone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(tone == .neutral ? Color.secondary : tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tone == .neutral
                      ? Color.primary.opacity(0.06)
                      : tone.color.opacity(tone.fillOpacity))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

/// YapYap-style status disc (success/running/danger).
struct StatusDot: View {
    var tone: SemanticTone = .success
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
