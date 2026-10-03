import SwiftUI

struct QuotaSection: View {
    @Environment(QuotaModel.self) private var quotaModel
    let provider: QuotaProvider

    var body: some View {
        switch quotaModel.statuses[provider].latest {
        case .unavailable:
            EmptyView()
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
                    ForEach(snapshot.windows, id: \.title) { window in
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

private let quotaBarHeight: CGFloat = 5

private struct QuotaWindowRow: View {
    let provider: Provider
    let window: QuotaWindow

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.title)
                    .fontWeight(.semibold)

                Spacer(minLength: 12)

                Text("\(window.usedPercent)% used")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .numericTextTransition()

                if let resetsAt = window.resetsAt {
                    QuotaDeadlineLabel(deadline: resetsAt)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)

            ProgressView(value: Double(window.usedPercent), total: 100)
                .progressViewStyle(QuotaProgressViewStyle())
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
                .frame(height: quotaBarHeight)
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
        .help(deadline.formatted(date: .complete, time: .shortened))
    }
}

func quotaTimeRemainingText(until date: Date, now: Date) -> String {
    let seconds = max(Int(date.timeIntervalSince(now)), 0)
    if seconds >= 86_400 {
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
    }
    if seconds >= 3_600 {
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h"
    }
    if seconds >= 60 {
        return "in \(seconds / 60)m"
    }
    return "soon"
}

private struct QuotaProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Color.primary
                .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
        }
        .frame(height: quotaBarHeight)
        .background(Color.primary.opacity(0.10))
        .clipShape(Capsule())
        // Flattened so the panel's Liquid Glass vibrancy cannot dim the fill to gray.
        .drawingGroup()
    }
}
