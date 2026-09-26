import Foundation
import UserNotifications

@MainActor
final class BreakReminderNotificationCenter: NSObject, BreakReminderNotifications {
    nonisolated private static let requestIdentifier = "break-reminder"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) {
        let isAuthorized: Bool
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            throw .schedulingFailed
        }
        guard isAuthorized else {
            throw .notificationsDisabled
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
            throw .schedulingFailed
        }
    }

    func hasDeliverableReminder() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return await center.pendingNotificationRequests().contains {
                $0.identifier == Self.requestIdentifier
            }
        case .notDetermined, .denied:
            return false
        @unknown default:
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
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            notification.request.identifier == Self.requestIdentifier
                ? [.banner, .list, .sound]
                : []
        )
    }
}
