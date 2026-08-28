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

            if let selectedDay {
                RuleMark(x: .value("Selected day", selectedDay.date, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(
                            x: .fit(to: .chart),
                            y: .disabled
                        )
                    ) {
                        UsageChartAnnotation(day: selectedDay)
                    }
            }
        }
        .chartXScale(domain: month.range.lowerBound...month.range.upperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .frame(height: 48)
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
