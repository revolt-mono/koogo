import Shimmer
import SwiftUI

/// The usage page composes three features: usage summary and provider cards,
/// quick actions, and the Codex quota folded into the Codex card.
struct UsagePage: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(CodexQuotaModel.self) private var codexQuotaModel
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
                                case .claude, .piAgent, .grok:
                                    ProviderUsageCard(provider: provider, usage: usage)
                                }
                            }
                        }
                    }
                    // Animated here so sibling cards follow the Codex card as its quota section resizes.
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.25),
                        value: codexQuotaModel.state
                    )
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
