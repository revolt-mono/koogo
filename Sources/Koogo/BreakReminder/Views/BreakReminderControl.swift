import SwiftUI

struct BreakReminderControl: View {
    @Environment(BreakReminderModel.self) private var reminderModel
    @State private var isVisible = false
    @State private var issue: BreakReminderIssue?

    var body: some View {
        // A stable container, so appearance tracks the control rather than whichever branch is showing.
        ZStack {
            if isVisible, case .running = reminderModel.countdown.status(at: .now) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    button(at: timeline.date)
                }
            } else {
                button(at: .now)
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .task {
            issue = await reminderModel.reconcile()
        }
        .breakReminderIssueAlert($issue)
    }

    private func button(at date: Date) -> some View {
        BreakReminderButton(status: reminderModel.countdown.status(at: date), isBusy: reminderModel.isBusy) { action in
            Task {
                issue = await reminderModel.perform(action)
            }
        }
    }
}

private struct BreakReminderButton: View {
    let status: BreakReminderStatus
    let isBusy: Bool
    let perform: (BreakReminderCountdown.Action) -> Void

    private var systemImage: String {
        switch status {
        case .running:
            "pause.fill"
        case .paused:
            "play.fill"
        case .expired:
            "figure.walk"
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .running:
            "Break reminder running"
        case .paused:
            "Break reminder paused"
        case .expired:
            "Break reminder finished"
        }
    }

    private var help: String {
        switch status {
        case .running:
            "Click to pause. Right-click to restart."
        case .paused:
            "Click to resume. Right-click to restart."
        case .expired:
            "Click to start a new reminder."
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .running:
            .primary
        case .paused:
            .secondary
        case .expired:
            .orange
        }
    }

    var body: some View {
        Button {
            perform(.toggle)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 7, weight: .semibold))
                    .frame(width: 6)

                Text(status.timeText)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
            .frame(height: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .disabled(isBusy)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(status.timeText)
        .accessibilityHint(help)
        .accessibilityAction(named: "Restart Timer") {
            perform(.restart)
        }
        .contextMenu {
            Button("Restart Timer") {
                perform(.restart)
            }
            .disabled(isBusy)
        }
    }
}

extension BreakReminderStatus {
    /// The time left as `h:mm:ss`, or `mm:ss` under an hour; an expired reminder shows zero.
    var timeText: String {
        let remaining: TimeInterval =
            switch self {
            case .running(let value), .paused(let value): value
            case .expired: 0
            }

        let totalSeconds = Int(ceil(remaining))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
