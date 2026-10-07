import SwiftUI

/// The recent samples as bars that fill in from the left on a fixed scale. Plain shapes, because a Swift Charts redraw inside the panel allocates about 86 MB of graphics memory per sample, and `Color.primary` fills turn gray under the glass vibrancy.
struct ActivityTrendChart: View {
    private static let height: CGFloat = 48

    let trend: ActivityTrend

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<ActivityModel.historyLength, id: \.self) { index in
                let value = index < trend.values.count ? trend.values[index] : 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: .labelColor))
                    .frame(width: 3, height: Self.height * value)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
