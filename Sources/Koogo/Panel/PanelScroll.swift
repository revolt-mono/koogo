import SwiftUI

extension View {
    /// Fades the content edges and keeps the margins in step with the fade; the scroller sits past `trailingInset`, outside the fade.
    func panelScroll(edgeFade: CGFloat, bottomInset: CGFloat? = nil, trailingInset: CGFloat) -> some View {
        contentMargins(.top, edgeFade, for: .scrollContent)
            .contentMargins(.bottom, bottomInset ?? edgeFade, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .mask {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: edgeFade)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: edgeFade)
                    }
                    Rectangle()
                        .frame(width: trailingInset)
                }
            }
    }
}
