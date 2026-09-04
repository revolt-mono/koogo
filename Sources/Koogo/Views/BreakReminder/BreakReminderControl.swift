import SwiftUI

struct BreakReminderControl: View {
    @Environment(BreakReminderModel.self) private var reminderModel
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible, case .running = reminderModel.status(at: .now) {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    BreakReminderButton(status: reminderModel.status(at: timeline.date))
                }
            } else {
                BreakReminderButton(status: reminderModel.status(at: .now))
            }
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }
}

private struct BreakReminderButton: View {
    @Environment(BreakReminderModel.self) private var reminderModel

    let status: BreakReminderStatus

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
        let timeText = breakReminderTimeText(status)

        Button {
            Task {
                await reminderModel.perform(.toggle)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 7, weight: .semibold))
                    .frame(width: 6)

                Text(timeText)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
            .frame(height: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .disabled(reminderModel.isScheduling)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(timeText)
        .accessibilityHint(help)
        .accessibilityAction(named: "Restart Timer") {
            restart()
        }
        .contextMenu {
            Button("Restart Timer", action: restart)
                .disabled(reminderModel.isScheduling)
        }
    }

    private func restart() {
        Task {
            await reminderModel.perform(.restart)
        }
    }
}

func breakReminderTimeText(_ status: BreakReminderStatus) -> String {
    let remaining: TimeInterval
    switch status {
    case .running(let value), .paused(let value):
        remaining = value
    case .expired:
        remaining = 0
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

extension View {
    func breakReminderIssueAlert(_ reminderModel: BreakReminderModel) -> some View {
        let isPresented = Binding(
            get: { reminderModel.issue != nil },
            set: { isPresented in
                if !isPresented {
                    reminderModel.dismissIssue()
                }
            }
        )

        return alert(
            reminderModel.issue?.title ?? "Break Reminder",
            isPresented: isPresented,
            presenting: reminderModel.issue
        ) { _ in
            Button("OK", role: .cancel) {
                reminderModel.dismissIssue()
            }
        } message: { issue in
            Text(issue.message)
        }
    }
}
