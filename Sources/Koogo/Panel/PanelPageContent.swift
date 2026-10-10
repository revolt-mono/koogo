import SwiftUI

struct PanelPageContent<Value, Content: View>: View {
    let value: Value?
    let loadingText: String
    @ViewBuilder let content: (Value) -> Content

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
                Text(loadingText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .loadingShimmer()
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(.horizontal, PanelLayout.inset)
                    .padding(.vertical, 24)
                    .transition(.blurReplace)
            }
        }
        .motionAnimation(.smooth(duration: 0.35), value: value != nil)
    }
}
