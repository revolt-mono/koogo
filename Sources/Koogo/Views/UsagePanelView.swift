import SwiftUI

struct UsagePanelView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                UsageSummaryPeriod(title: "Today", usage: snapshot.summary.today)
                UsageSummaryPeriod(title: "Monthly", usage: snapshot.summary.month)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            QuickActionsControl()

            VStack(spacing: 12) {
                ProviderUsageSection(provider: .codex, usage: snapshot.codex)
                ProviderUsageSection(provider: .claude, usage: snapshot.claude)
                ProviderUsageSection(provider: .piAgent, usage: snapshot.piAgent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }
}

private struct UsageSummaryPeriod: View {
    let title: String
    let usage: UsageSummaryPeriodSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                UsageSummaryValueLine(usage: usage, fontSize: 18)
                UsageSummaryValueLine(usage: usage, fontSize: 15)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(UsageFormatting.cost(usage.current.costUSD))
                            .animatingNumericText(value: usage.current.costUSD)
                        UsageCostChangeCapsule(change: usage.costChange)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("and")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("\(UsageFormatting.tokens(usage.current.processedTokens)) tokens")
                            .animatingNumericText(value: usage.current.processedTokens)
                    }
                }
                .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.98),
                        Color.primary.opacity(0.72),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
        }
    }
}

private struct UsageSummaryValueLine: View {
    let usage: UsageSummaryPeriodSnapshot
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(UsageFormatting.cost(usage.current.costUSD))
                .animatingNumericText(value: usage.current.costUSD)

            UsageCostChangeCapsule(change: usage.costChange)

            Text("and")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text("\(UsageFormatting.tokens(usage.current.processedTokens)) tokens")
                .animatingNumericText(value: usage.current.processedTokens)
        }
        .font(.system(size: fontSize, weight: .bold))
        .fixedSize()
    }
}

private struct UsageCostChangeCapsule: View {
    let change: UsageCostChange

    var body: some View {
        let style: (prefix: String, fraction: Decimal, color: Color) =
            switch change {
            case .increase(let fraction):
                (
                    "+",
                    fraction,
                    Color(red: 0, green: 128.0 / 255, blue: 9.0 / 255)
                )
            case .decrease(let fraction):
                (
                    "-",
                    fraction,
                    Color(red: 182.0 / 255, green: 68.0 / 255, blue: 0)
                )
            case .unchanged:
                ("", 0, .secondary)
            }
        let percentage = UsageFormatting.percentage(style.fraction)

        Text(style.prefix + percentage)
            .animatingNumericText(value: change)
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                style.color.opacity(0.6),
                in: Capsule()
            )
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.bottom] + 2
            }
            .accessibilityRepresentation {
                switch change {
                case .increase:
                    Text("Cost increased \(percentage) from the previous period")
                case .decrease:
                    Text("Cost decreased \(percentage) from the previous period")
                case .unchanged:
                    Text("Cost unchanged from the previous period")
                }
            }
    }
}

private extension Text {
    func animatingNumericText<Value: Equatable>(value: Value) -> some View {
        contentTransition(.numericText())
            .animation(.smooth(duration: 0.35), value: value)
    }
}

private extension UsageProvider {
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .piAgent: "Pi"
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "OpenAISymbol"
        case .claude: "ClaudeSymbol"
        case .piAgent: "PiSymbol"
        }
    }

    var barColor: Color {
        switch self {
        case .codex: .primary
        case .claude: Color(red: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255)
        case .piAgent: .accentColor
        }
    }
}

private struct ProviderUsageSection: View {
    let provider: UsageProvider
    let usage: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderUsageHeader(provider: provider, favorite: usage.favorite)

            VStack(spacing: 12) {
                if provider == .codex {
                    CodexQuotaView()
                }

                MonthlyUsageChart(
                    month: usage.dailyMonth,
                    barColor: provider.barColor
                )

                VStack(spacing: 6) {
                    ProviderUsageRow(title: "Today", usage: usage.today)
                    ProviderUsageRow(title: "Weekly", usage: usage.week)
                    ProviderUsageRow(title: "Monthly", usage: usage.month)
                }
            }
            .padding(12)
            .background(
                Color.black.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }
}

private struct ProviderUsageHeader: View {
    let provider: UsageProvider
    let favorite: ProviderUsageSnapshot.Favorite?

    var body: some View {
        HStack(spacing: 4) {
            Image(provider.symbolName, bundle: .module)
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
                        Text("\(favorite.modelName) · \(effort)")
                    default:
                        Text(favorite.modelName)
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        // A 12-point inset matches the card content geometrically; 6 points aligns the header optically.
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

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                Text("\(UsageFormatting.tokens(usage.processedTokens)) tokens ·")
                    .foregroundStyle(.secondary)

                Text(UsageFormatting.cost(usage.costUSD))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
        }
        .font(.system(size: 9, weight: .medium))
        .frame(maxWidth: .infinity)
    }
}
