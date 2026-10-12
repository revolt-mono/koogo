import SwiftUI

extension View {
    /// The panel's badge: a small white label on a filled capsule.
    func capsuleBadge(_ fill: some ShapeStyle, weight: Font.Weight = .medium) -> some View {
        font(.system(size: 9, weight: weight))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }
}

extension Color {
    static let riseFill = Color(red: 0, green: 128 / 255, blue: 9 / 255).opacity(0.6)
    static let fallFill = Color(red: 182 / 255, green: 68 / 255, blue: 0).opacity(0.6)
    static let flatFill = Color.secondary.opacity(0.6)
}
