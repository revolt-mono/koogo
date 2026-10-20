import SwiftUI

struct QuotaSection: View {
    @Environment(QuotaModel.self) private var quotaModel
    @Environment(CodexQuotaResetModel.self) private var resetModel
    let provider: QuotaProvider

    var body: some View {
        switch quotaModel.statuses[provider].latest {
        case .unavailable:
            if provider == .codex, resetModel.hasResetActivity {
                VStack(spacing: 16) {
                    CodexQuotaResetView()
                    Divider()
                }
            }
        case nil:
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { _ in
                        QuotaWindowPlaceholder()
                    }
                }
                .foregroundStyle(.secondary.opacity(0.24))
                .loadingShimmer()
                .accessibilityLabel("Loading \(provider.provider.title) limits")
                Divider()
            }
        case .available(let snapshot):
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                        QuotaWindowRow(provider: provider.provider, window: window)
                    }
                    if let credits = snapshot.credits {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Credits")
                                .fontWeight(.semibold)
                            Spacer(minLength: 12)
                            switch credits {
                            case .balance(let balance):
                                Text(balance, format: .number.precision(.fractionLength(0...2)))
                            case .available:
                                Text("Available")
                            case .unlimited:
                                Text("Unlimited")
                            }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                    }
                    if provider == .codex {
                        CodexQuotaResetView()
                    }
                }
                Divider()
            }
        }
    }
}

private struct QuotaWindowRow: View {
    let provider: Provider
    let window: QuotaWindow

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.title)
                    .fontWeight(.semibold)

                Spacer(minLength: 12)

                RollingText(text: "\(window.usedPercent)% used")
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                if let resetsAt = window.resetsAt {
                    QuotaDeadlineLabel(deadline: resetsAt)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)

            ProgressView(value: Double(window.usedPercent), total: 100)
                .progressViewStyle(.panel)
                .accessibilityLabel("\(provider.title) \(window.title)")
                .accessibilityValue("\(window.usedPercent) percent used")
        }
    }
}

private struct QuotaWindowPlaceholder: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 44, height: 8)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 104, height: 8)
            }
            RoundedRectangle(cornerRadius: 2)
                .frame(height: PanelProgressViewStyle.height)
        }
    }
}

private struct QuotaDeadlineLabel: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Text("resets \(quotaTimeRemainingText(until: deadline, now: timeline.date))")
        }
        .foregroundStyle(.secondary)
        .tooltip(deadline.formatted(.display(date: .complete, time: .shortened)))
    }
}

func quotaTimeRemainingText(until date: Date, now: Date) -> String {
    let remaining = Duration.seconds(date.timeIntervalSince(now))
    guard remaining >= .seconds(60) else {
        return "soon"
    }
    return "in \(remaining.formatted(.displayUnits(allowed: [.days, .hours, .minutes])))"
}
