import SwiftUI

struct UsagePanelView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 18) {
            UsageSummaryView(snapshot: snapshot)

            Divider()

            VStack(spacing: 14) {
                ProviderUsageSection(provider: .codex, usage: snapshot.codex)
                ProviderUsageSection(provider: .claude, usage: snapshot.claude)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

private struct UsageSummaryView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UsageSummaryPeriod(title: "Today", usage: total(for: .today))
            UsageSummaryPeriod(title: "Monthly", usage: total(for: .month))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func total(for period: UsagePeriod) -> UsageTotal {
        let codex = snapshot.codex[period]
        let claude = snapshot.claude[period]
        return UsageTotal(
            processedTokens: codex.processedTokens + claude.processedTokens,
            costUSD: codex.costUSD + claude.costUSD
        )
    }
}

private struct UsageTotal {
    let processedTokens: Decimal
    let costUSD: Decimal
}

private struct UsageSummaryPeriod: View {
    let title: String
    let usage: UsageTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(UsageFormatting.cost(usage.costUSD))

                Text("and")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens")
            }
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.72),
                        Color.primary.opacity(0.95),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }
}

private struct ProviderUsageSection: View {
    let provider: UsageProvider
    let usage: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                symbol
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                Text(provider.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }

            VStack(spacing: 12) {
                MonthlyUsageChart(month: usage.dailyMonth)

                VStack(spacing: 6) {
                    ProviderUsageRow(title: "Today", usage: usage.today)
                    ProviderUsageRow(title: "Weekly", usage: usage.week)
                    ProviderUsageRow(title: "Monthly", usage: usage.month)
                }
            }
            .padding(12)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }

    private var symbol: Image {
        switch provider {
        case .codex: Image("OpenAISymbol", bundle: .module)
        case .claude: Image("ClaudeSymbol", bundle: .module)
        }
    }
}

private struct ProviderUsageRow: View {
    let title: String
    let usage: UsagePeriodSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .fontWeight(.medium)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens ·")
                    .foregroundStyle(.secondary)

                Text(UsageFormatting.cost(usage.costUSD))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
        }
        .font(.system(size: 10, design: .rounded))
        .frame(maxWidth: .infinity)
    }
}
