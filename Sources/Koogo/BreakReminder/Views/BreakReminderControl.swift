import SwiftUI

struct BreakReminderControl: View {
    @Environment(BreakReminderModel.self) private var reminderModel
    @State private var isVisible = false
    @State private var issue: BreakReminderIssue?

    var body: some View {
        ZStack {
            if isVisible, case .running = reminderModel.status {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    button(status: reminderModel.countdown.status(at: timeline.date))
                }
            } else {
                button(status: reminderModel.status)
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

    private func button(status: BreakReminderStatus) -> some View {
        BreakReminderButton(status: status, isBusy: reminderModel.isBusy) { action in
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
