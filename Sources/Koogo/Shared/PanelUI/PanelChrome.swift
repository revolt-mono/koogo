import SwiftUI

enum PanelLayout {
    static let inset: CGFloat = 20
    static let gap: CGFloat = 12
    static let pageIndicatorInset: CGFloat = 32
}

struct PanelSection<Header: View, Content: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
                .padding(.horizontal, 6)

            content()
                .padding(12)
                .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

            if let subtitle {
                Spacer(minLength: 0)

                Text(subtitle)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

struct PanelProgressViewStyle: ProgressViewStyle {
    static let height: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        Color.panelLabel
            .scaleEffect(x: configuration.fractionCompleted ?? 0, anchor: .leading)
            .frame(height: Self.height)
            .background(Color.panelLabel.opacity(0.10))
            .clipShape(Capsule())
    }
}

extension ProgressViewStyle where Self == PanelProgressViewStyle {
    static var panel: PanelProgressViewStyle { PanelProgressViewStyle() }
}

extension ShapeStyle where Self == Color {
    static var panelRaised: Color { .white.opacity(0.06) }

    /// the primary swiftui color turns gray under glass vibrancy.
    static var panelLabel: Color { Color(nsColor: .labelColor) }
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
