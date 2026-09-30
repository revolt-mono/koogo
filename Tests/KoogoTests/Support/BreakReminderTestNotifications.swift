import Foundation

@testable import Koogo

@MainActor
final class BreakReminderTestNotifications: BreakReminderNotifications {
    var beforeOperation: (() async -> Void)?
    var schedulingIssue: BreakReminderIssue?
    var scheduledDurations: [TimeInterval] = []
    var cancellationCount = 0
    var isReminderPending = false

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) {
        await beforeOperation?()
        if let schedulingIssue {
            throw schedulingIssue
        }
        scheduledDurations.append(duration)
        isReminderPending = true
    }

    func isPending() async -> Bool {
        await beforeOperation?()
        return isReminderPending
    }

    func cancel() {
        cancellationCount += 1
        isReminderPending = false
    }
}
