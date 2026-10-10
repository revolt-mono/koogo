import SwiftUI

/// The newest samples that fit as bars on a fixed scale, filling in from the left. A plain shape rather than Swift Charts, which allocated about 86 MB of graphics memory per redraw inside the panel. Bar edges snap to the pixel grid so the gaps stay crisp at any width.
struct ActivityTrendChart: View {
    let trend: ActivityTrend

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Bars(values: trend.values, displayScale: displayScale)
            // `Color.primary` turns gray under the panel's glass vibrancy.
            .fill(Color(nsColor: .labelColor))
            .frame(height: 32)
            .accessibilityHidden(true)
    }

    private struct Bars: Shape {
        private static let slot: CGFloat = 4
        private static let gap: CGFloat = 1

        let values: [Double]
        let displayScale: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            for (index, value) in values.suffix(Int(rect.width / Self.slot)).enumerated() {
                let left = snapped(Self.slot * CGFloat(index))
                let right = snapped(Self.slot * CGFloat(index + 1)) - Self.gap
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
