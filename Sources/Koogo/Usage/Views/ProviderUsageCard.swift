import SwiftUI

struct ProviderUsageCard<Accessory: View>: View {
    let provider: Provider
    let usage: ProviderUsageSnapshot
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderUsageHeader(provider: provider, favorite: usage.favorite)

            VStack(spacing: 12) {
                accessory()

                DailyUsageChart(usage: usage.dailyLast30Days)

                VStack(spacing: 6) {
                    ProviderUsageRow(title: "Today", usage: usage.today)
                    ProviderUsageRow(title: "Last 7 days", usage: usage.last7Days)
                    ProviderUsageRow(title: "Last 30 days", usage: usage.last30Days)
                }
            }
            .padding(12)
            .background(
                Color.black.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }
}

private struct ProviderUsageHeader: View {
    let provider: Provider
    let favorite: ProviderUsageSnapshot.Favorite?

    var body: some View {
        HStack(spacing: 4) {
            Image(provider.symbolAsset, bundle: .module)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            Text(provider.title)
                .font(.system(size: 11, weight: .semibold))

            if let favorite {
                Spacer(minLength: 12)

                Image("FavoriteHeart", bundle: .module)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 12)
                    .accessibilityHidden(true)

                Group {
                    switch favorite.reasoningEffort {
                    case .some(let effort) where effort != "off":
                        Text("\(favorite.modelName) in \(effort)")
                    default:
                        Text(favorite.modelName)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct ProviderUsageRow: View {
    let title: String
    let usage: UsagePeriodSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens ·")
                    .foregroundStyle(.secondary)

                Text(UsageFormatting.cost(usage.costUSD))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
        }
        .font(.system(size: 9, weight: .medium))
        .frame(maxWidth: .infinity)
    }
}
