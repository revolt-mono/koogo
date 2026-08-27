import SwiftUI

struct UsagePanelView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 20) {
            UsageSummaryView(snapshot: snapshot)

            Divider()

            VStack(spacing: 12) {
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
        let summary = snapshot.summary

        VStack(alignment: .leading, spacing: 12) {
            UsageSummaryPeriod(title: "Today", usage: summary.today)
            UsageSummaryPeriod(title: "Monthly", usage: summary.month)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageSummaryPeriod: View {
    let title: String
    let usage: UsageSummaryPeriodSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                UsageSummaryValueLine(usage: usage, fontSize: 18)
                UsageSummaryValueLine(usage: usage, fontSize: 15)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(UsageFormatting.cost(usage.cost.currentUSD))
                        UsageCostChangeCapsule(change: usage.cost.change)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("and")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens")
                    }
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
            }
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
            .minimumScaleFactor(0.7)
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }
}

private struct UsageSummaryValueLine: View {
    let usage: UsageSummaryPeriodSnapshot
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(UsageFormatting.cost(usage.cost.currentUSD))

            UsageCostChangeCapsule(change: usage.cost.change)

            Text("and")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens")
        }
        .font(.system(size: fontSize, weight: .bold, design: .rounded))
        .fixedSize()
    }
}

private struct UsageCostChangeCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    let change: UsageCostChange

    var body: some View {
        let percentage = UsageFormatting.percentage(change.fraction)
        let style: (text: String, color: Color, accessibilityLabel: String) = switch change.direction {
        case .increase:
            (
                "+\(percentage)",
                Color(red: 0, green: 128.0 / 255, blue: 9.0 / 255),
                "Cost increased \(percentage) from the previous period"
            )
        case .decrease:
            (
                "-\(percentage)",
                Color(red: 182.0 / 255, green: 68.0 / 255, blue: 0),
                "Cost decreased \(percentage) from the previous period"
            )
        case .unchanged:
            (
                percentage,
                .secondary,
                "Cost unchanged from the previous period"
            )
        }

        Text(style.text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                style.color.opacity(colorScheme == .dark ? 0.6 : 0.82),
                in: Capsule()
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.bottom] + 2
            }
            .accessibilityRepresentation {
                Text(style.accessibilityLabel)
            }
    }
}

private struct ProviderUsageSection: View {
    let provider: UsageProvider
    let usage: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                symbol
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                Text(provider.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))

                if let favorite = usage.favorite {
                    Spacer(minLength: 12)

                    Image("FavoriteHeart", bundle: .module)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 12)
                        .accessibilityHidden(true)

                    Text(
                        favorite.reasoningEffort.map {
                            "\(favorite.modelName) with \($0)"
                        } ?? favorite.modelName
                    )
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
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
                .fill.quaternary,
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
        .font(.system(size: 9, design: .rounded))
        .frame(maxWidth: .infinity)
    }
}
