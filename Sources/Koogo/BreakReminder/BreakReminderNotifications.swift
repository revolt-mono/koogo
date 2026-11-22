import Foundation

@MainActor
protocol BreakReminderNotifications {
  func schedule(after duration: TimeInterval) async throws(BreakReminderIssue)
  func hasPendingReminder() async -> Bool
  func cancel()
}

enum BreakReminderIssue: Error {
  case notificationsDeclined
  /// macos prompts only once, so only system settings can allow notifications after a denial.
  case notificationsBlocked
  case schedulingFailed

  var explanation: String {
    switch self {
    case .notificationsDeclined,
         .notificationsBlocked:
      "Notifications are off. Allow them in System Settings, then resume the reminder."
    case .schedulingFailed:
      "Koogo couldn't schedule the notification. Resume the reminder to try again."
    }
  }
}
