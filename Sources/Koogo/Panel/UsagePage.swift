import Shimmer
import SwiftUI

/// The usage page composes three features: usage summary and provider cards,
/// quick actions, and the Codex and Grok quotas folded into their cards.
struct UsagePage: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(CodexQuotaModel.self) private var codexQuotaModel
    @Environment(GrokQuotaModel.self) private var grokQuotaModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let snapshot = usageModel.snapshot {
                VStack(spacing: 20) {
                    UsageSummaryView(summary: snapshot.summary)

                    QuickActionsControl()

                    VStack(spacing: 12) {
                        ForEach(UsageProvider.allCases, id: \.self) { provider in
                            if let usage = snapshot.providers[provider] {
                                switch provider {
                                case .codex:
                                    ProviderUsageCard(provider: provider, usage: usage) {
                                        CodexQuotaView()
                                    }
                                case .grok:
                                    ProviderUsageCard(provider: provider, usage: usage) {
                                        GrokQuotaView()
                                    }
                                case .claude, .piAgent:
                                    ProviderUsageCard(provider: provider, usage: usage)
                                }
                            }
                        }
                    }
                    // Animated here so sibling cards follow a card as its quota section resizes.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: codexQuotaModel.state)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: grokQuotaModel.state)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .transition(.blurReplace)
            } else {
                Text("Parsing logs…")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .shimmering(active: !reduceMotion)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .transition(.blurReplace)
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.35),
            value: usageModel.snapshot != nil
        )
    }
}
