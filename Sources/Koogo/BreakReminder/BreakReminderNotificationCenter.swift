import Foundation
import UserNotifications
import os

@MainActor
final class BreakReminderNotificationCenter: NSObject, BreakReminderNotifications {
    nonisolated private static let requestIdentifier = "break-reminder"

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) {
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

        let content = UNMutableNotificationContent()
        content.title = "Time to Stand Up"
        content.body = "Take a short walk, restart your timer when you're back."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(duration, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: trigger
        )

        center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
        do {
            try await center.add(request)
        } catch {
            Logger.app.warning("break reminder scheduling failed: \(error, privacy: .public)")
            throw .schedulingFailed
        }
    }

    func hasPendingReminder() async -> Bool {
        // the center isn't sendable, so each concurrent read takes its own handle.
        async let status = UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        async let identifiers = UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        switch await status {
        case .authorized, .provisional:
            return await identifiers.contains(Self.requestIdentifier)
        default:
            return false
        }
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }
}

extension BreakReminderNotificationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier == Self.requestIdentifier ? [.banner, .list, .sound] : []
    }
}
