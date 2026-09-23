import SwiftUI

struct UsageSummaryView: View {
    let summary: UsageSummarySnapshot

    var body: some View {
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                UsageSummaryValueLine(usage: usage, fontSize: 18)
                UsageSummaryValueLine(usage: usage, fontSize: 15)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        AnimatedNumericText(text: UsageFormatting.cost(usage.current.costUSD))
                        UsageCostChangeCapsule(change: usage.costChange)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("and")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        AnimatedNumericText(
                            text: "\(UsageFormatting.tokens(usage.current.processedTokens)) tokens"
                        )
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
            AnimatedNumericText(text: UsageFormatting.cost(usage.current.costUSD))

            UsageCostChangeCapsule(change: usage.costChange)

            Text("and")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            AnimatedNumericText(
                text: "\(UsageFormatting.tokens(usage.current.processedTokens)) tokens"
            )
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

        AnimatedNumericText(text: style.prefix + percentage)
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

private struct AnimatedNumericText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String

    var body: some View {
        Text(text)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: text)
    }
}
