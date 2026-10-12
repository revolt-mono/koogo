import SwiftUI

extension View {
    func panelPageScroll() -> some View {
        contentMargins(.top, PanelLayout.gap, for: .scrollContent)
            .contentMargins(.leading, PanelLayout.inset, for: .scrollContent)
            .contentMargins(.bottom, PanelLayout.bottomInset, for: .scrollContent)
            .panelScroll(fadeDepth: 64, scrollerInset: PanelLayout.inset)
    }

    /// Fades content where it scrolls past an edge, deepening with the distance scrolled up to `fadeDepth`, so content at rest stays crisp. The trailing `scrollerInset` holds the scroller and stays unfaded.
    func panelScroll(fadeDepth: CGFloat, scrollerInset: CGFloat) -> some View {
        contentMargins(.trailing, scrollerInset, for: .scrollContent)
            .modifier(ScrollEdgeFade(fadeDepth: fadeDepth, scrollerInset: scrollerInset))
    }
}

private struct ScrollEdgeFade: ViewModifier {
    private static let smoothstepRamp = Gradient(
        stops: stride(from: 0.0, through: 1, by: 0.125).map { location in
            .init(color: .black.opacity(location * location * (3 - 2 * location)), location: location)
        }
    )

    let fadeDepth: CGFloat
    let scrollerInset: CGFloat

    @State private var depths = EdgeDepths()

    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: EdgeDepths.self) { geometry in
                let above = geometry.contentInsets.top + geometry.visibleRect.minY
                let below = geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY
                return EdgeDepths(top: min(max(above, 0), fadeDepth), bottom: min(max(below, 0), fadeDepth))
            } action: { _, newDepths in
                depths = newDepths
            }
            .mask {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        LinearGradient(gradient: Self.smoothstepRamp, startPoint: .top, endPoint: .bottom)
                            .frame(height: depths.top)
                        Rectangle()
                        LinearGradient(gradient: Self.smoothstepRamp, startPoint: .bottom, endPoint: .top)
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
