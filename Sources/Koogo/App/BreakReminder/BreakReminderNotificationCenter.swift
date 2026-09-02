import Foundation
import UserNotifications

@MainActor
final class BreakReminderNotificationCenter: NSObject, BreakReminderNotifications {
    private static let requestIdentifier = "break-reminder"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) -> Date {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw BreakReminderIssue.notificationsDisabled
            }

            let content = UNMutableNotificationContent()
            content.title = "Time to Stand Up"
            content.body = "Take a short walk, restart your timer when you're back."
            content.sound = .default

            let scheduledDuration = max(duration, 1)
            let deadline = Date.now.addingTimeInterval(scheduledDuration)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: scheduledDuration,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.requestIdentifier,
                content: content,
                trigger: trigger
            )

            center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
            try await center.add(request)
            return deadline
        } catch let issue as BreakReminderIssue {
            throw issue
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

extension BreakReminderNotificationCenter: @MainActor UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let options: UNNotificationPresentationOptions =
            notification.request.identifier == Self.requestIdentifier
            ? [.banner, .list, .sound]
            : []
        completionHandler(options)
    }
}
