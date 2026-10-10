import SwiftUI

struct UsagePage: View {
    private static let headerGap: CGFloat = 20
    /// The cards scroll's edge fades carry part of the gaps around it.
    private static let cardsGap = headerGap - PanelLayout.gap
    private static let cardsBottomInset = PanelLayout.bottomInset - PanelLayout.gap

    @Environment(ProviderPreferences.self) private var preferences
    @Environment(UsageModel.self) private var usageModel
    @State private var headerHeight: CGFloat = 0

    let maxHeight: CGFloat

    var body: some View {
        PanelPageContent(usageModel.snapshot, loading: "Parsing logs…") { snapshot in
            VStack(spacing: Self.cardsGap) {
                VStack(spacing: Self.headerGap) {
                    UsageSummaryView(summary: snapshot.summary)

                    QuickActionsControl()
                }
                .padding(.horizontal, PanelLayout.inset)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    headerHeight = height
                }

                ProviderCards(
                    cards: preferences.usageProviders.compactMap { provider in
                        snapshot.providers[provider].map { (provider: provider, usage: $0) }
                    },
                    heightLimit: max(maxHeight - headerHeight - Self.cardsGap - Self.cardsBottomInset, 0)
                )
            }
            .padding(.bottom, Self.cardsBottomInset)
        }
    }
}

private struct ProviderCards: View {
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
            + PanelLayout.gap * CGFloat(max(leading.count - 1, 0) + 2)

        ScrollView {
            VStack(spacing: PanelLayout.gap) {
                ForEach(cards, id: \.provider) { card in
                    ProviderUsageCard(provider: card.provider, usage: card.usage) {
                        if let quota = preferences.quotaProvider(for: card.provider) {
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
            .padding(.horizontal, PanelLayout.inset)
            .motionAnimation(.smooth(duration: 0.25), value: quotaModel.statuses)
        }
        .panelScroll(edgeFade: PanelLayout.gap, scrollerInset: PanelLayout.inset)
        .frame(height: min(visibleHeight.rounded(.up), heightLimit))
    }
}
