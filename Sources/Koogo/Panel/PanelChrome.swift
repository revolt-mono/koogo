import SwiftUI

extension View {
    func panelCard() -> some View {
        padding(12)
            .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func panelSectionTitle() -> some View {
        font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
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
