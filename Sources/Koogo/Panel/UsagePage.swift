import SwiftUI

struct UsagePage: View {
  let maxHeight: CGFloat
  let isShown: Bool

  var body: some View {
    let awaitedQuota = preferences.quotaProviders.filter { quotaModel.statuses[$0].latest == nil }
    // every page takes this page's height, so the quota its placeholder awaits is due even off screen.
    let dueQuota = isShown ? preferences.quotaProviders : awaitedQuota
    PanelPageContent(awaitedQuota.isEmpty ? usageModel.snapshot : nil, loading: "Loading…") { snapshot in
      VStack(spacing: Self.cardsGapExcludingScrollMargin) {
        VStack(spacing: Self.headerGap) {
          UsageSummaryView(summary: snapshot.summary)

          QuickActionsControl()
        }
        .padding(.horizontal, PanelLayout.inset)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

        ProviderCards(
          cards: preferences.order.compactMap { provider in
            snapshot.providers[provider].map { (provider: provider, usage: $0) }
          },
          heightLimit: max(maxHeight - headerHeight - Self.cardsGapExcludingScrollMargin, 0),
        )
      }
    }
    .task(id: preferences.usageProviders) {
      usageModel.refresh(providers: preferences.usageProviders)
    }
    .task(id: dueQuota) {
      quotaModel.refresh(dueQuota)
    }
  }

  private static let headerGap: CGFloat = 20
  private static let cardsGapExcludingScrollMargin = headerGap - PanelLayout.gap

  @Environment(ProviderPreferences.self) private var preferences
  @Environment(UsageModel.self) private var usageModel
  @Environment(QuotaModel.self) private var quotaModel
  @State private var headerHeight: CGFloat = 0
}

private struct ProviderCards: View {
  let cards: [(provider: Provider, usage: ProviderUsageSnapshot)]
  let heightLimit: CGFloat

  var body: some View {
    let leading = cards.prefix(Self.visibleCards)
    let visibleHeight =
      leading.reduce(0) { $0 + cardHeights[$1.provider] }
        + PanelLayout.gap * CGFloat(max(leading.count, 1)) + PanelLayout.pageIndicatorInset

    ScrollView {
      VStack(spacing: PanelLayout.gap) {
        ForEach(cards, id: \.provider) { card in
          let quota = card.provider.quota
          ProviderUsageCard(
            provider: card.provider,
            usage: card.usage,
            plan: quota.flatMap { quotaModel.statuses[$0].latest?.snapshot?.plan },
          ) {
            if let quota {
              QuotaSection(provider: quota)
            }
          }
          .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardHeights[card.provider] = $0 }
        }
      }
      .motionAnimation(.smooth(duration: 0.25), value: quotaModel.statuses)
    }
    .panelPageScroll()
    .frame(height: min(visibleHeight.rounded(.up), heightLimit))
  }

  private static let visibleCards = 3

  @Environment(QuotaModel.self) private var quotaModel
  @State private var cardHeights = EnumMap<Provider, CGFloat> { _ in 0 }
}
