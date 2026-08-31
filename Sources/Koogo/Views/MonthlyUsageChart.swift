import AppKit
import Charts
import SwiftUI

struct MonthlyUsageChart: View {
    let month: UsageMonthSnapshot
    let barColor: Color

    @State private var selectedDate: Date?

    private var selectedDay: UsageDaySnapshot? {
        guard let selectedDate else {
            return nil
        }
        return month.days.first {
            Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        Chart {
            ForEach(month.days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Cost", NSDecimalNumber(decimal: day.costUSD).doubleValue)
                )
                .foregroundStyle(barColor)
                .cornerRadius(1)
            }
        }
        .chartXScale(domain: month.range.lowerBound...month.range.upperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let selectedDay, let plotFrame = proxy.plotFrame,
                    let selectedX = proxy.position(forX: selectedDay.date)
                {
                    // A mark annotation changes the plot origin as its content moves.
                    ChartAnnotationLayout(anchorX: geometry[plotFrame].minX + selectedX) {
                        UsageChartAnnotation(day: selectedDay)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 48)
        .animation(.smooth(duration: 0.35), value: month)
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
                y: bounds.minY
            ),
            anchor: .top,
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
                .foregroundStyle(Color(nsColor: .labelColor))

            Text(
                "\(UsageFormatting.cost(day.costUSD)) · "
                    + "\(UsageFormatting.tokens(day.processedTokens)) tokens"
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
