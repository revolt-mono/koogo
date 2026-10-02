import SwiftUI

struct UsagePage: View {
    private static let headerGap: CGFloat = 20 - ProviderCards.spacing
    private static let bottomInset: CGFloat = 32 - ProviderCards.spacing

    @Environment(ProviderPreferences.self) private var preferences
    @Environment(UsageModel.self) private var usageModel
    @State private var headerHeight: CGFloat = 0

    let maxHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if let snapshot = usageModel.snapshot {
                VStack(spacing: Self.headerGap) {
                    VStack(spacing: 20) {
                        UsageSummaryView(summary: snapshot.summary)

                        QuickActionsControl()
                    }
                    .padding(.horizontal, 20)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        headerHeight = height
                    }

                    ProviderCards(
                        cards: preferences.usageProviders.compactMap { provider in
                            snapshot.providers[provider].map { (provider: provider, usage: $0) }
                        },
                        heightLimit: max(maxHeight - headerHeight - Self.headerGap - Self.bottomInset, 0)
                    )
                }
                .padding(.bottom, Self.bottomInset)
                .transition(.blurReplace)
            } else {
                Text("Parsing logs…")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .loadingShimmer()
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .transition(.blurReplace)
            }
        }
        .motionAnimation(.smooth(duration: 0.35), value: usageModel.snapshot != nil)
    }
}

private struct ProviderCards: View {
    fileprivate static let spacing: CGFloat = 12
    private static let inset: CGFloat = 20
    private static let visibleCards = 3

    @Environment(ProviderPreferences.self) private var preferences
    @Environment(QuotaModel.self) private var quotaModel
    @State private var cardHeights: [Provider: CGFloat] = [:]

    let cards: [(provider: Provider, usage: ProviderUsageSnapshot)]
    let heightLimit: CGFloat

    var body: some View {
        let leading = cards.prefix(Self.visibleCards)
        let visibleHeight =
            leading.compactMap { cardHeights[$0.provider] }.reduce(0, +)
            + Self.spacing * CGFloat(max(leading.count - 1, 0) + 2)

        ScrollView {
            VStack(spacing: Self.spacing) {
                ForEach(cards, id: \.provider) { card in
                    ProviderUsageCard(provider: card.provider, usage: card.usage) {
                        if let quota = card.provider.quota, preferences.quotaProviders.contains(quota) {
                            QuotaSection(provider: quota)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        cardHeights[card.provider] = height
                    }
                }
            }
            .padding(.horizontal, Self.inset)
            .motionAnimation(.smooth(duration: 0.25), value: quotaModel.statuses)
        }
        .contentMargins(.vertical, Self.spacing, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .mask {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.spacing)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.spacing)
                }
                Rectangle()
                    .frame(width: Self.inset)
            }
        }
        .frame(height: min(visibleHeight.rounded(.up), heightLimit))
    }
}
