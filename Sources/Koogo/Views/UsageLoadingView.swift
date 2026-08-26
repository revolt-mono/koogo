import Shimmer
import SwiftUI

struct UsageLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Parsing logs…")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .shimmering(active: !reduceMotion)
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
    }
}
