import SwiftUI

extension View {
    func capsuleBadge(_ fill: some ShapeStyle, weight: Font.Weight = .medium) -> some View {
        font(.system(size: 9, weight: weight))
            .foregroundStyle(.panelLabel)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }
}
