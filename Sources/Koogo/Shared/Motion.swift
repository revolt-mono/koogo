import Shimmer
import SwiftUI

extension View {
    func motionAnimation(_ animation: Animation?, value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    func loadingShimmer() -> some View {
        modifier(LoadingShimmer())
    }

    /// Rolls changed digits in place. The transition is rasterized so each animation scale does not enter the system font cache.
    func numericTextTransition() -> some View {
        contentTransition(.numericText())
            .environment(\.contentTransitionAddsDrawingGroup, true)
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Rests while scrolled off screen, so a page waiting out of view costs no frames.
private struct LoadingShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = true

    func body(content: Content) -> some View {
        content
            .shimmering(active: !reduceMotion && isOnScreen)
            .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                isOnScreen = isVisible
            }
    }
}
