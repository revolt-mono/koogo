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
                    ForEach(UsagePeriod.allCases, id: \.self) { period in
                        ProviderUsagePeriodRow(
                            provider: provider,
                            period: period,
                            usage: usage.periods[period]
                        )
                    }
                }
                .font(.system(size: 9, weight: .medium))
            }
            .padding(12)
            .background(
                Color.black.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }
}

private struct ProviderUsagePeriodRow: View {
    @State private var isPresented = false

    let provider: Provider
    let period: UsagePeriod
    let usage: ProviderUsagePeriodSnapshot

    var body: some View {
        if let models = usage.models {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    ProviderUsageRow(title: period.title, usage: usage.total)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(provider.title) \(period.title) model usage")
            .panelPopover(isPresented: $isPresented) {
                ProviderUsageModelsView(title: period.title, models: models)
            }
        } else {
            ProviderUsageRow(title: period.title, usage: usage.total)
        }
    }
}

private struct ProviderUsageModelsView: View {
    let title: String
    let models: [ModelUsageSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .fontWeight(.semibold)

            if models.isEmpty {
                Text("No usage during this period")
                    .foregroundStyle(.secondary)
            } else {
                let rowHeight: CGFloat = 16
                let rowSpacing: CGFloat = 8
                let contentHeight = CGFloat(models.count) * (rowHeight + rowSpacing) - rowSpacing
                let visibleHeight = min(contentHeight, 256)
                let scrollInsets =
                    contentHeight > visibleHeight
                    ? EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 16)
                    : EdgeInsets()

                ScrollView {
                    VStack(spacing: rowSpacing) {
                        ForEach(models) { model in
                            ProviderUsageRow(title: model.modelName, usage: model.usage)
                                .help(model.modelName)
                                .frame(height: rowHeight)
                        }
                    }
                }
                .contentMargins(.all, scrollInsets, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeFade(height: scrollInsets.top, trailingInset: scrollInsets.trailing)
                .frame(height: visibleHeight)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(16)
        .frame(width: 296)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension UsagePeriod {
    var title: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
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
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens ·")
                    .foregroundStyle(.secondary)

                Text(UsageFormatting.cost(usage.costUSD))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }
}
