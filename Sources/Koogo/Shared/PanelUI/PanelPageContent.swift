import Shimmer
import SwiftUI

struct PanelPageContent<Value, Content: View>: View {
    let value: Value?
    let loadingText: String
    let content: (Value) -> Content

    init(_ value: Value?, loading loadingText: String, @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.loadingText = loadingText
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let value {
                content(value)
                    .transition(.blurReplace)
            } else {
                LoadingLabel(text: loadingText)
                    .transition(.blurReplace)
            }
        }
        .motionAnimation(.smooth(duration: 0.35), value: value != nil)
    }
}

private struct LoadingLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = true

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .shimmering(active: !reduceMotion && isOnScreen)
            .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                isOnScreen = isVisible
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.horizontal, PanelLayout.inset)
            .padding(.vertical, 24)
    }
}
