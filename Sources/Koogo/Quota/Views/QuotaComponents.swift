import SwiftUI

/// One quota window: title, what is left, a live reset countdown, and a remaining-share bar.
struct QuotaWindowRow: View {
    let scopeTitle: String
    let title: String
    let window: QuotaWindow

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
                .progressViewStyle(QuotaProgressViewStyle())
                .accessibilityLabel("\(scopeTitle) \(title)")
                .accessibilityValue("\(window.remainingPercent) percent left")
        }
    }
}

/// The shape of a `QuotaWindowRow` while limits load; the caller styles and animates it.
struct QuotaWindowPlaceholder: View {
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
                .frame(height: 6)
        }
    }
}

/// Footnote under limits whose latest refresh failed.
struct QuotaStaleNotice: View {
    let isRefreshDisabled: Bool
    let refresh: () -> Void

    var body: some View {
        HStack {
            Text("Quota data may be out of date")
                .foregroundStyle(.secondary)
            Spacer()
            QuotaRefreshButton(isDisabled: isRefreshDisabled, action: refresh)
        }
        .font(.system(size: 9))
    }
}

struct QuotaRefreshButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Refresh")
        .disabled(isDisabled)
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

private struct QuotaProgressViewStyle: ProgressViewStyle {
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
