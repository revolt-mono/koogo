import SwiftUI

/// One provider's card: header with favorite model, an optional accessory
/// above the chart, then today/weekly/monthly rows.
struct ProviderUsageCard<Accessory: View>: View {
    let provider: UsageProvider
    let usage: ProviderUsageSnapshot
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderUsageHeader(provider: provider, favorite: usage.favorite)

            VStack(spacing: 12) {
                accessory()

                MonthlyUsageChart(
                    month: usage.dailyMonth,
                    barColor: provider.barColor
                )

                VStack(spacing: 6) {
                    ProviderUsageRow(title: "Today", usage: usage.today)
                    ProviderUsageRow(title: "Weekly", usage: usage.week)
                    ProviderUsageRow(title: "Monthly", usage: usage.month)
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

extension ProviderUsageCard where Accessory == EmptyView {
    init(provider: UsageProvider, usage: ProviderUsageSnapshot) {
        self.init(provider: provider, usage: usage) { EmptyView() }
    }
}

extension UsageProvider {
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .piAgent: "Pi"
        case .grok: "Grok"
        }
    }
}

private extension UsageProvider {
    var imageAssetName: String {
        switch self {
        case .codex: "OpenAISymbol"
        case .claude: "ClaudeSymbol"
        case .piAgent: "PiSymbol"
        case .grok: "GrokSymbol"
        }
    }

    var barColor: Color {
        switch self {
        case .codex, .grok: .primary
        case .claude: Color(red: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255)
        case .piAgent: .accentColor
        }
    }
}

private struct ProviderUsageHeader: View {
    let provider: UsageProvider
    let favorite: ProviderUsageSnapshot.Favorite?

    var body: some View {
        HStack(spacing: 4) {
            Image(provider.imageAssetName, bundle: .module)
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
        // A 12-point inset matches the card content geometrically; 6 points aligns the header optically.
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
