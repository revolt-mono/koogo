import SwiftUI

/// A page's stand-in while its first data arrives.
struct PanelLoadingText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .loadingShimmer()
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
    }
}
