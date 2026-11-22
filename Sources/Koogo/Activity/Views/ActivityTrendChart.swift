import SwiftUI

struct ActivityTrendChart: View {
  /// samples run oldest first, as fractions of chart height.
  let trend: [Double]

  var body: some View {
    TrendBars(values: trend, displayScale: displayScale)
      .fill(.panelLabel)
      .frame(height: 32)
      .accessibilityHidden(true)
  }

  @Environment(\.displayScale) private var displayScale
}

private struct TrendBars: SeriesShape {
  var values: [Double]
  let displayScale: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for (index, value) in values.suffix(Int(rect.width / Self.slotWidth)).enumerated() where value > 0 {
      let left = pixelSnapped(Self.slotWidth * CGFloat(index) + Self.gap / 2)
      let right = pixelSnapped(Self.slotWidth * CGFloat(index + 1) - Self.gap / 2)
      let height = rect.height * value
      path.addRect(CGRect(x: rect.minX + left, y: rect.maxY - height, width: right - left, height: height))
    }
    return path
  }

  private static let slotWidth: CGFloat = 4
  private static let gap: CGFloat = 1
}
