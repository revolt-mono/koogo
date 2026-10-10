import SwiftUI

extension View {
    /// Page content scrolls under the floating page indicator and fades at the panel edges.
    func panelPageScroll() -> some View {
        panelScroll(edgeFade: PanelLayout.gap, bottomInset: PanelLayout.bottomInset, scrollerInset: PanelLayout.inset)
    }

    func panelScroll(edgeFade: CGFloat, bottomInset: CGFloat? = nil, scrollerInset: CGFloat) -> some View {
        contentMargins(.top, edgeFade, for: .scrollContent)
            .contentMargins(.bottom, bottomInset ?? edgeFade, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .mask {
                let fade = Gradient(colors: [.clear, .black.opacity(0.3), .black])
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        LinearGradient(gradient: fade, startPoint: .top, endPoint: .bottom)
                            .frame(height: edgeFade)
                        Rectangle()
                        LinearGradient(gradient: fade, startPoint: .bottom, endPoint: .top)
                            .frame(height: edgeFade)
                    }
                    Rectangle()
                        .frame(width: scrollerInset)
                }
            }
    }
}
