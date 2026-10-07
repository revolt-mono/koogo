import Charts
import SwiftUI

/// The recent samples as bars that fill in from the left, on a fixed scale so a new sample never rescales the rest.
struct ActivityTrendChart: View {
    let trend: ActivityTrend

    var body: some View {
        Chart(Array(trend.values.enumerated()), id: \.offset) { sample in
            BarMark(
                x: .value("Sample", sample.offset),
                y: .value("Load", sample.element),
                width: .fixed(3)
            )
            .foregroundStyle(Color.primary)
            .cornerRadius(1)
        }
        .chartXScale(domain: -1...ActivityModel.historyLength)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 48)
        .accessibilityHidden(true)
    }
}
