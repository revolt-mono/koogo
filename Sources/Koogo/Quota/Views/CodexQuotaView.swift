import Shimmer
import SwiftUI

struct CodexQuotaView: View {
    @Environment(CodexQuotaModel.self) private var codexQuotaModel

    var body: some View {
        switch codexQuotaModel.state {
        case .unavailable:
            EmptyView()
        case .loading:
            VStack(spacing: 16) {
                CodexQuotaLoadingView()
                Divider()
            }
        case .available(let snapshot):
            VStack(spacing: 16) {
                CodexQuotaContent(snapshot: snapshot)
                if codexQuotaModel.refreshFailure != nil {
                    HStack {
                        Text("Quota data may be out of date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        CodexQuotaRefreshButton()
                    }
                    .font(.system(size: 9))
                }
                Divider()
            }
        }
    }
}

struct CodexQuotaRefreshButton: View {
    @Environment(CodexQuotaModel.self) private var model

    var body: some View {
        Button {
            model.refresh(force: true)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Refresh")
        .disabled(model.isRefreshing || model.isResetting)
    }
}

private struct CodexQuotaContent: View {
    let snapshot: CodexQuotaSnapshot

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                if let limits = snapshot.account?.limits {
                    CodexQuotaLimitsView(title: nil, limits: limits)
                }
                CodexQuotaResetView()
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
                    QuotaDeadlineLabel(deadline: resetsAt)
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
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Text("· resets \(quotaTimeRemainingText(until: deadline, now: timeline.date))")
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

private struct CodexQuotaProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let fraction = configuration.fractionCompleted ?? 0

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
