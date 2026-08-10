import SwiftUI

/// Quiet top-level header — wordmark-scale title, whisper subtitle (YapYap-like air).
struct PanelHeader<Trailing: View>: View {
    let systemImage: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        systemImage: String? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: VaakyaSpace.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: VaakyaSpace.sm) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .tracking(-0.3)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: VaakyaSpace.lg)
            trailing()
        }
        .padding(.horizontal, VaakyaSpace.panelInset)
        .padding(.top, VaakyaSpace.xl)
        .padding(.bottom, VaakyaSpace.lg)
        .accessibilityElement(children: .combine)
    }
}

/// Soft pill primary action — coral by default (YapYap energy).
struct SoftPillButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = true
    let action: () -> Void

    var body: some View {
        YapPillButton(title: title, systemImage: systemImage, filled: prominent, action: action)
    }
}
