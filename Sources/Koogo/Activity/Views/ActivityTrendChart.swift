import SwiftUI

struct ActivityTrendChart: View {
    let trend: ActivityTrend

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        BarChart(values: trend.values, slotWidth: 4, displayScale: displayScale)
            .fill(.panelLabel)
            .frame(height: 32)
            .accessibilityHidden(true)
    }
}
