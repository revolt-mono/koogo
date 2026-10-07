import SwiftUI

/// Recent samples as bars on a fixed scale, filling in from the left. A plain shape rather than Swift Charts, which allocated about 86 MB of graphics memory per redraw inside the panel. Bar edges snap to the pixel grid so the gaps stay crisp at any width.
struct ActivityTrendChart: View {
    let trend: ActivityTrend

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Bars(values: trend.values, displayScale: displayScale)
            // `Color.primary` turns gray under the panel's glass vibrancy.
            .fill(Color(nsColor: .labelColor))
            .frame(height: 48)
            .accessibilityHidden(true)
    }

    private struct Bars: Shape {
        let values: [Double]
        let displayScale: CGFloat

        func path(in rect: CGRect) -> Path {
            let slot = rect.width / CGFloat(ActivityModel.historyLength)
            let gap: CGFloat = 1
            var path = Path()
            for (index, value) in values.enumerated() {
                let left = snapped(slot * CGFloat(index))
                let right = snapped(slot * CGFloat(index + 1)) - gap
                let height = rect.height * value
                path.addRect(CGRect(x: rect.minX + left, y: rect.maxY - height, width: right - left, height: height))
            }
            return path
        }

        private func snapped(_ offset: CGFloat) -> CGFloat {
            (offset * displayScale).rounded() / displayScale
        }
    }
}
