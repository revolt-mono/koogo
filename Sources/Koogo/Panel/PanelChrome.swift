import SwiftUI

enum PanelLayout {
    static let inset: CGFloat = 20
    /// Between sections, and the depth of a scroll edge fade.
    static let gap: CGFloat = 12
    /// Room for the page indicator.
    static let bottomInset: CGFloat = 32
}

struct PanelSection<Header: View, Content: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
                .padding(.horizontal, 6)

            content()
                .panelCard()
        }
    }
}

extension PanelSection where Header == PanelSectionTitle {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(header: { PanelSectionTitle(title: title, subtitle: subtitle) }, content: content)
    }
}

struct PanelSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            if let subtitle {
                Spacer(minLength: 0)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    func panelCard() -> some View {
        padding(12)
            .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PanelProgressViewStyle: ProgressViewStyle {
    static let height: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Color.primary
                .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
        }
        .frame(height: Self.height)
        .background(Color.primary.opacity(0.10))
        .clipShape(Capsule())
        // Flattened so the panel's Liquid Glass vibrancy cannot dim the fill to gray.
        .drawingGroup()
    }
}

extension ProgressViewStyle where Self == PanelProgressViewStyle {
    static var panel: PanelProgressViewStyle { PanelProgressViewStyle() }
}

extension ShapeStyle where Self == Color {
    static var panelRaised: Color { .white.opacity(0.06) }
}

extension ShapeStyle where Self == LinearGradient {
    static var panelHeadline: LinearGradient {
        LinearGradient(
            colors: [Color.primary.opacity(0.98), Color.primary.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
