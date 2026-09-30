import SwiftUI

/// One quota window: title, what is used, a live reset countdown, and a used-share bar.
struct QuotaWindowRow: View {
    let scopeTitle: String
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
                .accessibilityLabel("\(scopeTitle) \(window.title)")
                .accessibilityValue("\(window.usedPercent) percent used")
        }
    }
}

/// One scope's windows; a model scope is named in a header and in the rows' accessibility labels.
struct QuotaWindowsView: View {
    let scopeTitle: String
    var header: String?
    let windows: [QuotaWindow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                QuotaScopeHeader(title: header)
            }
            ForEach(windows, id: \.title) { window in
                QuotaWindowRow(scopeTitle: scopeTitle, window: window)
            }
        }
    }
}

/// Names the model whose windows follow, with a rule filling the rest of the line.
private struct QuotaScopeHeader: View {
    let title: String

    var body: some View {
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
}

/// The shape of a `QuotaWindowRow` while limits load; callers style it and apply `loadingShimmer()`.
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
                .frame(height: quotaBarHeight)
        }
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

/// An odd height off the 2-point grid for compact internals, chosen by eye between 4 (too thin) and 6.
private let quotaBarHeight: CGFloat = 5

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
