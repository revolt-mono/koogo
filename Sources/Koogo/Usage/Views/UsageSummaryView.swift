import SwiftUI

struct UsageSummaryView: View {
    let summary: UsageSummarySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSummaryPeriod(title: UsagePeriod.today.title, usage: summary.today)
            UsageSummaryPeriod(title: UsagePeriod.last30Days.title, usage: summary.last30Days)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageSummaryPeriod: View {
    let title: String
    let usage: UsageSummaryPeriodSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelSectionTitle(title: title)

            ViewThatFits(in: .horizontal) {
                UsageSummaryLine(usage: usage, fontSize: 18)
                UsageSummaryLine(usage: usage, fontSize: 15)

                VStack(alignment: .leading, spacing: 2) {
                    UsageSummaryCost(usage: usage)
                    UsageSummaryTokens(usage: usage)
                }
                .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.panelHeadline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
        }
    }
}

private struct UsageSummaryLine: View {
    let usage: UsageSummaryPeriodSnapshot
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            UsageSummaryCost(usage: usage)
            UsageSummaryTokens(usage: usage)
        }
        .font(.system(size: fontSize, weight: .bold))
        .fixedSize()
    }
}

private struct UsageSummaryCost: View {
    let usage: UsageSummaryPeriodSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            AnimatedNumericText(text: usage.current.costUSD.formatted(.usd))
            UsageCostChangeCapsule(change: usage.costChange)
        }
    }
}

private struct UsageSummaryTokens: View {
    let usage: UsageSummaryPeriodSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("and")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            AnimatedNumericText(
                text: "\(usage.current.processedTokens.formatted(.compactTokens)) tokens"
            )
        }
    }
}

private struct UsageCostChangeCapsule: View {
    let change: UsageCostChange

    var body: some View {
        let (prefix, fraction, color): (String, Decimal, Color) =
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
        let percentage = fraction.formatted(.usagePercent)

        AnimatedNumericText(text: prefix + percentage)
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                color.opacity(0.6),
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
    @State private var isOnScreen = false

    let text: String

    var body: some View {
        // ViewThatFits keeps updating unselected candidates, and an animation started there never settles.
        Text(text)
            .numericTextTransition()
            .motionAnimation(isOnScreen ? .smooth(duration: 0.35) : nil, value: text)
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
    }
}
