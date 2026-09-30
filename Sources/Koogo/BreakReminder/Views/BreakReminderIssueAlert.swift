import SwiftUI

extension View {
    func breakReminderIssueAlert(_ issue: Binding<BreakReminderIssue?>) -> some View {
        alert(
            issue.wrappedValue?.title ?? "Break Reminder",
            isPresented: issue.isPresent(),
            presenting: issue.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { issue in
            Text(issue.message)
        }
    }
}

private extension BreakReminderIssue {
    var title: String {
        switch self {
        case .notificationsDisabled:
            "Notifications Are Off"
        case .schedulingFailed:
            "Couldn't Start Break Reminder"
        }
    }

    var message: String {
        switch self {
        case .notificationsDisabled:
            "Allow Koogo notifications in System Settings before starting the break reminder."
        case .schedulingFailed:
            "Koogo couldn't schedule the notification. Please try again."
        }
    }
}
