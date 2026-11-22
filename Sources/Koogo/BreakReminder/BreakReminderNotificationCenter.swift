import Foundation
import os
import UserNotifications

@MainActor
final class BreakReminderNotificationCenter: NSObject, BreakReminderNotifications {
  override init() {
    super.init()
    center.delegate = self
  }

  func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) {
    try await authorize()
    center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
    do {
      try await center.add(Self.request(after: duration))
    } catch {
      Logger.app.warning("break reminder scheduling failed: \(error, privacy: .public)")
      throw .schedulingFailed
    }
  }

  func hasPendingReminder() async -> Bool {
    // `UNUserNotificationCenter` is not sendable.
    async let status = UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    async let identifiers = UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    switch await status {
    case .authorized,
         .provisional:
      return await identifiers.contains(Self.requestIdentifier)
    default:
      return false
    }
  }

  func cancel() {
    center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
  }

  nonisolated private static let requestIdentifier = "break-reminder"

  private let center = UNUserNotificationCenter.current()

  private static func request(after duration: TimeInterval) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = "Time to Stand Up"
    content.body = "Take a short walk, restart your timer when you're back."
    content.sound = .default
    return UNNotificationRequest(
      identifier: requestIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(duration, 1), repeats: false),
    )
  }

  private func authorize() async throws(BreakReminderIssue) {
    guard await center.notificationSettings().authorizationStatus != .denied else {
      throw .notificationsBlocked
    }
    let isAuthorized: Bool
    do {
      isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
      Logger.app.warning("break reminder authorization failed: \(error, privacy: .public)")
      throw .schedulingFailed
    }
    guard isAuthorized else {
      throw .notificationsDeclined
    }
  }
}

extension BreakReminderNotificationCenter: UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _: UNUserNotificationCenter,
    willPresent notification: UNNotification,
  ) async -> UNNotificationPresentationOptions {
    if notification.request.identifier == Self.requestIdentifier {
      [.banner, .list, .sound]
    } else {
      []
    }
  }
}
