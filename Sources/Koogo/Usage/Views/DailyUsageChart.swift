import AppKit
import SwiftUI

struct DailyUsageChart: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.displayScale) private var displayScale

    let usage: UsageDailySnapshot

    @State private var hoveredSlot: Int?

    var body: some View {
        let days = Dictionary(usage.days.map { (slot(of: $0.date), $0) }) { _, newer in newer }
        let peakCost = usage.days.map(\.usage.costUSD).max() ?? 0
        let heights = (0..<slot(of: usage.range.upperBound)).map { slot in
            guard let day = days[slot], peakCost > 0 else { return 0.0 }
            return NSDecimalNumber(decimal: day.usage.costUSD / peakCost).doubleValue
        }

        GeometryReader { geometry in
            let slotWidth = geometry.size.width / CGFloat(heights.count)
            DotMatrixChart(values: heights, displayScale: displayScale)
                .fill(.panelLabel)
                .background {
                    DotMatrixChart(values: Array(repeating: 1, count: heights.count), displayScale: displayScale)
                        .fill(.panelLabel.opacity(0.08))
                }
                .onContinuousPointerHover { phase in
                    hoveredSlot = if case .active(let point) = phase { Int(point.x / slotWidth) } else { nil }
                }
                .overlay {
                    if let hoveredSlot, let day = days[hoveredSlot] {
                        ChartAnnotationLayout(anchorX: (CGFloat(hoveredSlot) + 0.5) * slotWidth) {
                            UsageChartAnnotation(day: day)
                        }
                        .allowsHitTesting(false)
                    }
                }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
        .motionAnimation(.smooth(duration: 0.35), value: usage)
    }

    /// Whole days from the start of the range, counted by day number so a day that starts after midnight still gets its own slot.
    private func slot(of date: Date) -> Int {
        let dayNumber = { calendar.ordinality(of: .day, in: .era, for: $0) ?? 0 }
        return dayNumber(date) - dayNumber(usage.range.lowerBound)
    }
}

private struct DotMatrixChart: Shape {
    private static let gap: CGFloat = 2

    var values: [Double]
    let displayScale: CGFloat

    var animatableData: AnimatableValues {
        get { AnimatableValues(values) }
        set { values = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        let slot = rect.width / CGFloat(values.count)
        guard slot.isFinite, slot > 0 else { return Path() }
        let rows = Int((rect.height + Self.gap) / slot)
        let cornerSize = CGSize(width: slot / 4, height: slot / 4)
        var path = Path()
        for (column, value) in values.enumerated() {
            let left = (slot * CGFloat(column) + Self.gap / 2).pixelSnapped(scale: displayScale)
            let right = (slot * CGFloat(column + 1) - Self.gap / 2).pixelSnapped(scale: displayScale)
            for row in 0..<Int((value * Double(rows)).rounded(.up)) {
                let bottom = (slot * CGFloat(row)).pixelSnapped(scale: displayScale)
                let top = (slot * CGFloat(row + 1) - Self.gap).pixelSnapped(scale: displayScale)
                path.addRoundedRect(
                    in: CGRect(x: rect.minX + left, y: rect.maxY - top, width: right - left, height: top - bottom),
                    cornerSize: cornerSize
                )
            }
        }
        return path
    }
}

private struct ChartAnnotationLayout: Layout {
    let anchorX: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let annotation = subviews[0]
        let size = annotation.sizeThatFits(.unspecified)
        annotation.place(
            at: CGPoint(
                x: min(
                    max(bounds.minX + anchorX, bounds.minX + size.width / 2),
                    bounds.maxX - size.width / 2
                ),
                y: bounds.minY - 4
            ),
            anchor: .bottom,
            proposal: .unspecified
        )
    }
}

private struct UsageChartAnnotation: View {
    let day: UsageDaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date, format: .dateTime.month(.abbreviated).day())
                .fontWeight(.semibold)
                .foregroundStyle(.panelLabel)

            Text(
                "\(day.usage.costUSD.formatted(.usd)) · "
                    + "\(day.usage.processedTokens.formatted(.compactTokens)) tokens"
            )
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .monospacedDigit()
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}
