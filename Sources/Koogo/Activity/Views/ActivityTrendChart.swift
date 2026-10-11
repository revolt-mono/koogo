import SwiftUI

struct ActivityTrendChart: View {
    let trend: ActivityTrend

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TrendBars(values: trend.values, displayScale: displayScale)
            .fill(.panelLabel)
            .frame(height: 32)
            .accessibilityHidden(true)
    }
}

private struct TrendBars: Shape {
    private static let slotWidth: CGFloat = 4
    private static let gap: CGFloat = 1

    var values: [Double]
    let displayScale: CGFloat

    var animatableData: AnimatableValues {
        get { AnimatableValues(values) }
        set { values = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in values.suffix(Int(rect.width / Self.slotWidth)).enumerated() where value > 0 {
            let left = (Self.slotWidth * CGFloat(index) + Self.gap / 2).pixelSnapped(scale: displayScale)
            let right = (Self.slotWidth * CGFloat(index + 1) - Self.gap / 2).pixelSnapped(scale: displayScale)
            let height = rect.height * value
            path.addRect(CGRect(x: rect.minX + left, y: rect.maxY - height, width: right - left, height: height))
        }
        return path
    }
}
