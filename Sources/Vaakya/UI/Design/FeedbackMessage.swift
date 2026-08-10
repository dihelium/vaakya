import SwiftUI

/// Inline operation result — soft card, not a hard alert strip.
struct FeedbackMessage: View {
    let text: String
    var tone: SemanticTone = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: VaakyaSpace.sm) {
            Image(systemName: systemImage ?? defaultIcon)
                .foregroundStyle(tone.color)
                .imageScale(.small)
                .padding(.top, 1)
            Text(text)
                .font(.callout)
                .foregroundStyle(tone == .neutral ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VaakyaSpace.lg)
        .padding(.vertical, VaakyaSpace.md)
        .background(
            RoundedRectangle(cornerRadius: VaakyaRadius.row)
                .fill(tone.color.opacity(tone == .neutral ? 0.06 : tone.fillOpacity * 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: VaakyaRadius.row)
                .strokeBorder(VaakyaSurface.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var defaultIcon: String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .neutral: return "text.alignleft"
        }
    }
}

/// Full-width soft banner (consent).
struct InfoBanner: View {
    let text: String
    var systemImage: String = "info.circle"
    var tone: SemanticTone = .info
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: VaakyaSpace.md) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(tone.color)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: VaakyaSpace.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, VaakyaSpace.panelInset)
        .padding(.vertical, VaakyaSpace.lg)
        .background(tone.color.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(VaakyaSurface.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
