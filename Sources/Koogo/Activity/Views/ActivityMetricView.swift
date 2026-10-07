import SwiftUI

/// One metric set like a provider card: a summary-style title and headline, then a card holding its details and trend.
struct ActivityMetricView: View {
    let title: String
    let subtitle: String
    let headline: ActivityFormatting.Measure
    let details: KeyValuePairs<String, String>
    let trend: ActivityTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .panelSectionTitle()

                    Spacer(minLength: 12)

                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(headline.value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.panelHeadline)

                    Text(headline.unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 12) {
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

                ActivityTrendChart(trend: trend)
            }
            .panelCard()
        }
    }
}
