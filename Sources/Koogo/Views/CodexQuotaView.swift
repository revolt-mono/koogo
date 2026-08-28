import Shimmer
import SwiftUI

struct CodexQuotaView: View {
    @Environment(CodexQuotaModel.self) private var codexQuotaModel

    var body: some View {
        Group {
            switch codexQuotaModel.state {
            case .hidden:
                EmptyView()
            case .loading:
                VStack(spacing: 16) {
                    CodexQuotaLoadingView()
                    Divider()
                }
            case .available(let snapshot):
                VStack(spacing: 16) {
                    CodexQuotaContent(snapshot: snapshot)
                    Divider()
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: codexQuotaModel.state)
    }
}

private struct CodexQuotaContent: View {
    let snapshot: CodexQuotaSnapshot

    var body: some View {
        VStack(spacing: 16) {
            if let account = snapshot.account {
                VStack(spacing: 8) {
                    if let limits = account.limits {
                        CodexQuotaLimitsView(title: nil, limits: limits)
                    }
                    if let resetCredits = account.resetCredits {
                        CodexQuotaResetRow(resetCredits: resetCredits)
                    }
                }
            }

            ForEach(snapshot.models) { model in
                CodexQuotaLimitsView(title: model.title, limits: model.limits)
            }
        }
    }
}

private struct CodexQuotaLimitsView: View {
    let title: String?
    let limits: CodexQuotaSnapshot.Limits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
            }

            if let fiveHour = limits.fiveHour {
                CodexQuotaWindowRow(
                    scopeTitle: title ?? "Codex",
                    title: "5h limit",
                    window: fiveHour
                )
            }
            if let weekly = limits.weekly {
                CodexQuotaWindowRow(
                    scopeTitle: title ?? "Codex",
                    title: "Weekly limit",
                    window: weekly
                )
            }
        }
    }
}

private struct CodexQuotaResetRow: View {
    let resetCredits: CodexQuotaSnapshot.ResetCredits

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Quota reset")
                .fontWeight(.semibold)

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(resetCredits.availableCount)")
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(" available")
                        .foregroundStyle(.secondary)
                }

                if let nextExpiration = resetCredits.nextExpiration {
                    QuotaDeadlineLabel(
                        action: resetCredits.availableCount == 1 ? "expires" : "next expires",
                        deadline: nextExpiration
                    )
                }
            }
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
    }
}

private struct CodexQuotaWindowRow: View {
    let scopeTitle: String
    let title: String
    let window: CodexQuotaSnapshot.Window

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)

                Spacer(minLength: 12)

                Text("\(window.remainingPercent)% left")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if let resetsAt = window.resetsAt {
                    QuotaDeadlineLabel(action: "resets", deadline: resetsAt)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .progressViewStyle(CodexQuotaProgressViewStyle())
                .accessibilityLabel("\(scopeTitle) \(title)")
                .accessibilityValue("\(window.remainingPercent) percent left")
        }
    }
}

private struct QuotaDeadlineLabel: View {
    let action: String
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Text("· \(action) \(quotaTimeRemainingText(until: deadline, now: timeline.date))")
        }
        .foregroundStyle(.secondary)
    }
}

func quotaTimeRemainingText(until date: Date, now: Date) -> String {
    let seconds = max(Int(date.timeIntervalSince(now)), 0)
    if seconds >= 86_400 {
        let days = seconds / 86_400
        return "in \(days) \(days == 1 ? "day" : "days")"
    }
    if seconds >= 3_600 {
        return "in \(seconds / 3_600)h"
    }
    if seconds >= 60 {
        return "in \(seconds / 60)m"
    }
    return "soon"
}

private struct CodexQuotaProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary,
                                Color.primary.opacity(0.42),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

private struct CodexQuotaLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 4) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: 44, height: 8)
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: 104, height: 8)
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .frame(height: 6)
                    }
                }
            }

            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 76, height: 8)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 52, height: 8)
            }
        }
        .foregroundStyle(.secondary.opacity(0.24))
        .shimmering(active: !reduceMotion)
        .accessibilityLabel("Loading account limits")
    }
}
