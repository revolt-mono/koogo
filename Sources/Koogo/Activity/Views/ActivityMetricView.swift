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
                        .font(.system(size: 10, weight: .semibold))

                    Spacer(minLength: 12)

                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(headline.value)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.primary.opacity(0.98),
                                    Color.primary.opacity(0.72),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

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
            .padding(12)
            .background(
                Color.black.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }
}
