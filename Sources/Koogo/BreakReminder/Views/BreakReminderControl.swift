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

    private struct Appearance {
        let systemImage: String
        let color: Color
        let label: String
        let help: String
    }

    private var appearance: Appearance {
        switch status {
        case .running:
            Appearance(
                systemImage: "pause.fill",
                color: .primary,
                label: "Break reminder running",
                help: "Click to pause. Right-click to restart."
            )
        case .paused:
            Appearance(
                systemImage: "play.fill",
                color: .secondary,
                label: "Break reminder paused",
                help: "Click to resume. Right-click to restart."
            )
        case .expired:
            Appearance(
                systemImage: "figure.walk",
                color: .orange,
                label: "Break reminder finished",
                help: "Click to start a new reminder."
            )
        }
    }

    var body: some View {
        let appearance = appearance

        Button {
            perform(.toggle)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appearance.systemImage)
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
        .foregroundStyle(appearance.color)
        .disabled(isBusy)
        .help(appearance.help)
        .accessibilityLabel(appearance.label)
        .accessibilityValue(status.timeText)
        .accessibilityHint(appearance.help)
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
