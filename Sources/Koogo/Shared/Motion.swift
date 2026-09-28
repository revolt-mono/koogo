import Shimmer
import SwiftUI

/// The single owner of Reduce Motion for decorative animation, loading shimmer, and numeric transitions.
extension View {
    /// Animates changes to `value`, or applies them without animation when Reduce Motion is on.
    func motionAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// Shimmers a loading placeholder unless Reduce Motion is on.
    func loadingShimmer() -> some View {
        modifier(LoadingShimmer())
    }

    /// Rolls changed digits in place. The transition is rasterized so each animation scale does not enter
    /// the system font cache.
    func numericTextTransition() -> some View {
        contentTransition(.numericText())
            .environment(\.contentTransitionAddsDrawingGroup, true)
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct LoadingShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.shimmering(active: !reduceMotion)
    }
}
