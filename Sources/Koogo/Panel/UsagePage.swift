import SwiftUI

/// The usage page composes three features: usage summary and provider cards,
/// quick actions, and the Codex and Grok quotas folded into their cards.
struct UsagePage: View {
    /// The visible gaps above and below the cards are 20 and 32 points; the cards' scroll margins supply
    /// `ProviderCards.spacing` of each.
    private static let headerGap: CGFloat = 20 - ProviderCards.spacing
    private static let bottomInset: CGFloat = 32 - ProviderCards.spacing

    @Environment(UsageModel.self) private var usageModel
    @State private var headerHeight: CGFloat = 0

    /// The page never grows past this; only the provider cards give up height to stay within it.
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
                        providers: snapshot.providers,
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

/// The provider cards scroll on their own, tall enough to show the first two unless the screen is
/// shorter, so the totals and quick actions above stay in reach.
private struct ProviderCards: View {
    /// The gap between cards, reused as the scroll margin and fade band at each edge: at rest both bands
    /// cover only empty gaps, so the viewport shows exactly the first two cards.
    fileprivate static let spacing: CGFloat = 12
    /// Horizontal card inset; the scroller lives in the trailing one.
    private static let inset: CGFloat = 20

    @Environment(CodexQuotaModel.self) private var codexQuotaModel
    @Environment(GrokQuotaModel.self) private var grokQuotaModel
    @State private var cardHeights: [UsageProvider: CGFloat] = [:]

    let providers: [UsageProvider: ProviderUsageSnapshot]
    let heightLimit: CGFloat

    var body: some View {
        let shown = UsageProvider.allCases.filter { providers[$0] != nil }
        let leading = shown.prefix(2)
        let visibleHeight =
            leading.compactMap { cardHeights[$0] }.reduce(0, +)
            + Self.spacing * CGFloat(max(leading.count - 1, 0) + 2)

        ScrollView {
            VStack(spacing: Self.spacing) {
                ForEach(shown, id: \.self) { provider in
                    if let usage = providers[provider] {
                        ProviderUsageCard(provider: provider, usage: usage) {
                            switch provider {
                            case .codex: CodexQuotaView()
                            case .grok: GrokQuotaView()
                            case .claude, .piAgent: EmptyView()
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            cardHeights[provider] = height
                        }
                    }
                }
            }
            .padding(.horizontal, Self.inset)
            // Animated here so sibling cards follow a card as its quota section resizes.
            .motionAnimation(.smooth(duration: 0.25), value: codexQuotaModel.state)
            .motionAnimation(.smooth(duration: 0.25), value: grokQuotaModel.state)
        }
        .contentMargins(.vertical, Self.spacing, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
        .mask {
            // Fade the cards only, so the scroller in the trailing inset stays whole.
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
        // A fixed height keeps the page's ideal height independent of what the pager proposes.
        .frame(height: min(visibleHeight.rounded(.up), heightLimit))
    }
}
