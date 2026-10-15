import SwiftUI

struct BreakReminderControl: View {
    private static let notificationsPane = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )!

    @Environment(BreakReminderModel.self) private var reminderModel
    @Environment(\.openURL) private var openURL
    @State private var isOnScreen = false

    var body: some View {
        ZStack {
            let status = reminderModel.countdown.status(at: .now)
            if isOnScreen, case .running = status {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    button(status: reminderModel.countdown.status(at: timeline.date))
                }
            } else {
                button(status: status)
            }
        }
        .onAppear {
            isOnScreen = true
        }
        .onDisappear {
            isOnScreen = false
        }
        .task {
            await reminderModel.reconcile()
        }
    }

    private func button(status: BreakReminderStatus) -> some View {
        BreakReminderButton(status: status, issue: reminderModel.issue, isBusy: reminderModel.isBusy) { action in
            // The first refusal comes through the system prompt; only a click on an already orange timer leads to System Settings.
            let wasRefused = reminderModel.issue == .notificationsDisabled
            Task {
                await reminderModel.perform(action)
                if wasRefused, reminderModel.issue == .notificationsDisabled {
                    openURL(Self.notificationsPane)
                }
            }
        }
    }
}

private struct BreakReminderButton: View {
    let status: BreakReminderStatus
    let issue: BreakReminderIssue?
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
                color: issue == nil ? .secondary : .orange,
                label: "Break reminder paused",
                help: issue?.explanation ?? "Click to resume. Right-click to restart."
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
        .tooltip(appearance.help)
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
