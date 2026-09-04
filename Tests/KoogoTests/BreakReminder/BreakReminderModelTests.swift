import Foundation
import XCTest

@testable import Koogo

@MainActor
final class BreakReminderModelTests: XCTestCase {
    private final class TestClock {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }

    func testDefaultsToPausedSixtyMinuteReminder() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = BreakReminderModel(
            notifications: TestNotifications(),
            defaults: defaults
        )

        XCTAssertEqual(model.interval, .oneHour)
        XCTAssertEqual(model.status(at: .now), .paused(remaining: 3_600))
    }

    func testRunningReminderPausesAndResumesFromRemainingTime() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let notifications = TestNotifications(now: { clock.now })
        let model = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )

        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDeadlines, [clock.now.addingTimeInterval(3_600)])
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 3_600))

        clock.now.addTimeInterval(900)
        await model.perform(.toggle)

        XCTAssertEqual(model.status(at: clock.now), .paused(remaining: 2_700))
        XCTAssertEqual(notifications.cancellationCount, 1)

        clock.now.addTimeInterval(300)
        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDeadlines.last, clock.now.addingTimeInterval(2_700))
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 2_700))
    }

    func testRestartAndExpiredReminderUseFullSelectedInterval() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let notifications = TestNotifications(now: { clock.now })
        let model = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )
        await model.perform(.setInterval(.ninetyMinutes))
        await model.perform(.toggle)
        clock.now.addTimeInterval(600)

        await model.perform(.restart)

        XCTAssertEqual(notifications.scheduledDeadlines.last, clock.now.addingTimeInterval(5_400))
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 5_400))

        clock.now.addTimeInterval(5_401)
        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDeadlines.last, clock.now.addingTimeInterval(5_400))
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 5_400))
    }

    func testChangingIntervalResetsRunningAndPausedReminders() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let notifications = TestNotifications(now: { clock.now })
        let model = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )
        await model.perform(.toggle)
        clock.now.addTimeInterval(600)

        await model.perform(.setInterval(.twoHours))

        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 7_200))
        XCTAssertEqual(notifications.scheduledDeadlines.last, clock.now.addingTimeInterval(7_200))

        await model.perform(.toggle)
        await model.perform(.setInterval(.ninetyMinutes))

        XCTAssertEqual(model.status(at: clock.now), .paused(remaining: 5_400))
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testSchedulingIssuesKeepReminderPaused() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let notifications = TestNotifications()
        let model = BreakReminderModel(
            notifications: notifications,
            defaults: defaults
        )

        for issue in [BreakReminderIssue.notificationsDisabled, .schedulingFailed] {
            notifications.schedulingIssue = issue
            await model.perform(.toggle)

            XCTAssertEqual(model.status(at: .now), .paused(remaining: 3_600))
            XCTAssertEqual(model.issue, issue)
        }

        XCTAssertTrue(notifications.scheduledDeadlines.isEmpty)
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testStatePersistsAcrossModelInstances() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let model = BreakReminderModel(
            notifications: TestNotifications(now: { clock.now }),
            defaults: defaults,
            now: { clock.now }
        )
        await model.perform(.setInterval(.twoHours))
        await model.perform(.toggle)
        clock.now.addTimeInterval(900)

        let restoredModel = BreakReminderModel(
            notifications: TestNotifications(now: { clock.now }),
            defaults: defaults,
            now: { clock.now }
        )

        XCTAssertEqual(restoredModel.interval, .twoHours)
        XCTAssertEqual(restoredModel.status(at: clock.now), .running(remaining: 6_300))

        await restoredModel.perform(.toggle)
        let restoredPausedModel = BreakReminderModel(
            notifications: TestNotifications(now: { clock.now }),
            defaults: defaults,
            now: { clock.now }
        )

        XCTAssertEqual(restoredPausedModel.interval, .twoHours)
        XCTAssertEqual(restoredPausedModel.status(at: clock.now), .paused(remaining: 6_300))
    }

    func testReconciliationKeepsExistingAndRestoresMissingSystemNotification() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let notifications = TestNotifications(now: { clock.now })
        let firstModel = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )
        await firstModel.perform(.toggle)

        let restoredModel = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )
        await restoredModel.perform(.reconcile)
        XCTAssertEqual(notifications.scheduledDeadlines, [Date(timeIntervalSince1970: 4_600)])

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        await restoredModel.perform(.reconcile)

        XCTAssertTrue(notifications.isReminderPending)
        XCTAssertEqual(
            notifications.scheduledDeadlines,
            [Date(timeIntervalSince1970: 4_600), Date(timeIntervalSince1970: 4_600)]
        )
        XCTAssertEqual(restoredModel.status(at: clock.now), .running(remaining: 2_700))
    }

    func testReconciliationPausesWhenNotificationsAreDisabled() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let notifications = TestNotifications(now: { clock.now })
        let firstModel = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )
        await firstModel.perform(.toggle)

        clock.now.addTimeInterval(900)
        notifications.notificationsEnabled = false
        let restoredModel = BreakReminderModel(
            notifications: notifications,
            defaults: defaults,
            now: { clock.now }
        )

        await restoredModel.perform(.reconcile)

        XCTAssertEqual(restoredModel.status(at: clock.now), .paused(remaining: 2_700))
        XCTAssertEqual(restoredModel.issue, .notificationsDisabled)
        XCTAssertFalse(notifications.isReminderPending)
    }

    func testActionsAreIgnoredUntilReconciliationFinishes() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = Date(timeIntervalSince1970: 1_000)
        let notifications = TestNotifications(now: { date })
        let model = BreakReminderModel(notifications: notifications, defaults: defaults, now: { date })
        await model.perform(.toggle)
        notifications.isReminderPending = false

        var continuation: CheckedContinuation<Void, Never>?
        notifications.beforeOperation = {
            guard continuation == nil else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        let reconciliation = Task { await model.perform(.reconcile) }
        let deadline = ContinuousClock.now + .seconds(1)
        while continuation == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let resume = try XCTUnwrap(continuation)
        XCTAssertTrue(model.isScheduling)

        for action: BreakReminderModel.Action in [.toggle, .restart, .setInterval(.twoHours), .reconcile] {
            await model.perform(action)
        }
        XCTAssertTrue(model.isScheduling)
        XCTAssertEqual(model.interval, .oneHour)
        XCTAssertEqual(notifications.scheduledDeadlines.count, 1)
        XCTAssertEqual(notifications.cancellationCount, 0)

        resume.resume()
        await reconciliation.value
        XCTAssertFalse(model.isScheduling)
        XCTAssertEqual(model.status(at: date), .running(remaining: 3_600))
        XCTAssertEqual(notifications.scheduledDeadlines.count, 2)
    }

    func testTimeTextUsesHoursOnlyWhenNeeded() {
        XCTAssertEqual(breakReminderTimeText(.paused(remaining: 7_200)), "2:00:00")
        XCTAssertEqual(breakReminderTimeText(.running(remaining: 3_599.1)), "1:00:00")
        XCTAssertEqual(breakReminderTimeText(.running(remaining: 3_599)), "59:59")
        XCTAssertEqual(breakReminderTimeText(.expired), "00:00")
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BreakReminderModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private final class TestNotifications: BreakReminderNotifications {
    private let now: @MainActor () -> Date

    var beforeOperation: (() async -> Void)?
    var schedulingIssue: BreakReminderIssue?
    var scheduledDeadlines: [Date] = []
    var cancellationCount = 0
    var notificationsEnabled = true
    var isReminderPending = false

    init(now: @escaping @MainActor () -> Date = { .now }) {
        self.now = now
    }

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) -> Date {
        await beforeOperation?()
        guard notificationsEnabled else {
            throw .notificationsDisabled
        }
        if let schedulingIssue {
            throw schedulingIssue
        }
        let deadline = now().addingTimeInterval(duration)
        scheduledDeadlines.append(deadline)
        isReminderPending = true
        return deadline
    }

    func hasDeliverableReminder() async -> Bool {
        await beforeOperation?()
        return notificationsEnabled && isReminderPending
    }

    func cancel() {
        cancellationCount += 1
        isReminderPending = false
    }
}
