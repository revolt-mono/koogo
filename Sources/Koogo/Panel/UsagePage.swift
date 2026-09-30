import SwiftUI

struct UsagePage: View {
    private static let headerGap: CGFloat = 20 - ProviderCards.spacing
    private static let bottomInset: CGFloat = 32 - ProviderCards.spacing

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
                        order: usageModel.providerOrder,
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

private struct ProviderCards: View {
    fileprivate static let spacing: CGFloat = 12
    private static let inset: CGFloat = 20

    @Environment(QuotaModel.self) private var quotaModel
    @State private var cardHeights: [Provider: CGFloat] = [:]

    let order: [Provider]
    let providers: [Provider: ProviderUsageSnapshot]
    let heightLimit: CGFloat

    var body: some View {
        let shown = order.filter { providers[$0] != nil }
        let leading = shown.prefix(3)
        let visibleHeight =
            leading.compactMap { cardHeights[$0] }.reduce(0, +)
            + Self.spacing * CGFloat(max(leading.count - 1, 0) + 2)

        ScrollView {
            VStack(spacing: Self.spacing) {
                ForEach(shown, id: \.self) { provider in
                    if let usage = providers[provider] {
                        ProviderUsageCard(provider: provider, usage: usage) {
                            QuotaSection(provider: provider)
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
            .motionAnimation(.smooth(duration: 0.25), value: quotaModel.states)
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
