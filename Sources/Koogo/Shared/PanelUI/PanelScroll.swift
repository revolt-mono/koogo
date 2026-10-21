import SwiftUI

extension View {
    func panelPageScroll() -> some View {
        contentMargins(.top, PanelLayout.gap, for: .scrollContent)
            .contentMargins(.leading, PanelLayout.inset, for: .scrollContent)
            .contentMargins(.bottom, PanelLayout.pageIndicatorInset, for: .scrollContent)
            .panelScroll(scrollerInset: PanelLayout.inset)
    }

    /// fades scrolled edges while leaving the trailing scroller inset unfaded.
    func panelScroll(scrollerInset: CGFloat) -> some View {
        contentMargins(.trailing, scrollerInset, for: .scrollContent)
            .modifier(ScrollEdgeFade(scrollerInset: scrollerInset))
    }
}

private struct ScrollEdgeFade: ViewModifier {
    private static let fadeDepth: CGFloat = 64
    /// the edge-fade ramp from blog.x.com, eased at both ends so the boundary stays unnoticed.
    private static let ramp = Gradient(
        stops: [
            (0, 0), (0.15, 0.05), (0.3, 0.18),
            (0.45, 0.38), (0.6, 0.62), (0.75, 0.83),
            (0.87, 0.95), (0.95, 0.99), (1, 1),
        ]
        .map { location, opacity in .init(color: .black.opacity(opacity), location: location) }
    )

    let scrollerInset: CGFloat

    @State private var depths = EdgeDepths()

    /// grows the fade faster than the hidden distance so a row cut by the edge never gets a compressed, hard ramp.
    private static func depth(hiding distance: CGFloat) -> CGFloat {
        min((max(distance, 0) * fadeDepth).squareRoot(), fadeDepth)
    }

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: EdgeDepths.self) { geometry in
                let above = geometry.contentInsets.top + geometry.visibleRect.minY
                let below = geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY
                return EdgeDepths(top: Self.depth(hiding: above), bottom: Self.depth(hiding: below))
            } action: { _, newDepths in
                depths = newDepths
            }
            .mask {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        LinearGradient(gradient: Self.ramp, startPoint: .top, endPoint: .bottom)
                            .frame(height: depths.top)
                        Rectangle()
                        LinearGradient(gradient: Self.ramp, startPoint: .bottom, endPoint: .top)
                            .frame(height: depths.bottom)
                    }
                    Rectangle()
                        .frame(width: scrollerInset)
                }
            }
    }
}

private struct EdgeDepths: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
}
