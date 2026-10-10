import SwiftUI

struct ActivityLoadTile: View {
    let title: String
    let subtitle: String
    let headline: ActivityFormatting.Measure
    let details: KeyValuePairs<String, String>
    let trend: ActivityTrend

    var body: some View {
        PanelSection {
            VStack(alignment: .leading, spacing: 4) {
                PanelSectionTitle(title: title, subtitle: subtitle)

                ActivityHeadline(measure: headline)
            }
        } content: {
            VStack(spacing: 12) {
                ActivityDetails(details: details)

                ActivityTrendChart(trend: trend)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActivityHeadline: View {
    let measure: ActivityFormatting.Measure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(measure.value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.panelHeadline)

            Text(measure.unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

struct ActivityDetails: View {
    let details: KeyValuePairs<String, String>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(details), id: \.key) { detail in
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.key)
                        .foregroundStyle(.secondary)

                    Text(detail.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 9, weight: .medium))
    }
}
