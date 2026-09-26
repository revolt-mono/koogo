import Foundation
import XCTest

@testable import Koogo

@MainActor
final class BreakReminderModelTests: XCTestCase {
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    func testMissingOrInvalidPersistedStateFallsBackToPausedHour() throws {
        let outOfRangePause = try PropertyListSerialization.data(
            fromPropertyList: ["paused": ["interval": 60, "remaining": 9_999.0] as [String: Any]],
            format: .binary,
            options: 0
        )

        for payload in [nil, Data("garbage".utf8), outOfRangePause] {
            let defaults = try makeIsolatedDefaults()
            defaults.set(payload, forKey: "break-reminder-state")

            let model = makeModel(defaults: defaults)

            XCTAssertEqual(model.interval, .oneHour)
            XCTAssertEqual(model.status(at: .now), .paused(remaining: 3_600))
        }
    }

    func testRunningReminderPausesAndResumesFromRemainingTime() async throws {
        let clock = TestClock()
        let notifications = TestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 3_600))

        clock.now.addTimeInterval(900)
        await model.perform(.toggle)

        XCTAssertEqual(model.status(at: clock.now), .paused(remaining: 2_700))
        XCTAssertEqual(notifications.cancellationCount, 1)

        clock.now.addTimeInterval(300)
        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDurations, [3_600, 2_700])
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 2_700))
    }

    func testDeadlineStartsWhenSchedulingReturns() async throws {
        let clock = TestClock()
        let notifications = TestNotifications()
        // Stands in for an authorization prompt that stays open for 30 seconds.
        notifications.beforeOperation = { clock.now.addTimeInterval(30) }
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        await model.perform(.toggle)

        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 3_600))
    }

    func testRestartAndExpiredReminderUseFullSelectedInterval() async throws {
        let clock = TestClock()
        let notifications = TestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)
        await model.perform(.setInterval(.ninetyMinutes))
        await model.perform(.toggle)
        clock.now.addTimeInterval(600)

        await model.perform(.restart)

        XCTAssertEqual(notifications.scheduledDurations, [5_400, 5_400])
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 5_400))

        clock.now.addTimeInterval(5_401)
        await model.perform(.toggle)

        XCTAssertEqual(notifications.scheduledDurations, [5_400, 5_400, 5_400])
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 5_400))
    }

    func testChangingIntervalResetsRunningAndPausedReminders() async throws {
        let clock = TestClock()
        let notifications = TestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)
        await model.perform(.toggle)
        clock.now.addTimeInterval(600)

        await model.perform(.setInterval(.twoHours))

        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 7_200))
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 7_200])

        await model.perform(.toggle)
        await model.perform(.setInterval(.ninetyMinutes))

        XCTAssertEqual(model.status(at: clock.now), .paused(remaining: 5_400))
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testSchedulingIssuesKeepReminderPaused() async throws {
        let notifications = TestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), notifications: notifications)

        for issue in [BreakReminderIssue.notificationsDisabled, .schedulingFailed] {
            notifications.schedulingIssue = issue
            await model.perform(.toggle)

            XCTAssertEqual(model.status(at: .now), .paused(remaining: 3_600))
            XCTAssertEqual(model.issue, issue)
        }

        XCTAssertTrue(notifications.scheduledDurations.isEmpty)
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testStatePersistsAcrossModelInstances() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let model = makeModel(defaults: defaults, clock: clock)
        await model.perform(.setInterval(.twoHours))
        await model.perform(.toggle)
        clock.now.addTimeInterval(900)

        let restoredModel = makeModel(defaults: defaults, clock: clock)

        XCTAssertEqual(restoredModel.interval, .twoHours)
        XCTAssertEqual(restoredModel.status(at: clock.now), .running(remaining: 6_300))

        await restoredModel.perform(.toggle)
        let restoredPausedModel = makeModel(defaults: defaults, clock: clock)

        XCTAssertEqual(restoredPausedModel.interval, .twoHours)
        XCTAssertEqual(restoredPausedModel.status(at: clock.now), .paused(remaining: 6_300))
    }

    func testReconciliationKeepsExistingAndRestoresMissingSystemNotification() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = TestNotifications()
        await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
        await restoredModel.perform(.reconcile)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        await restoredModel.perform(.reconcile)

        XCTAssertTrue(notifications.isReminderPending)
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 2_700])
        XCTAssertEqual(restoredModel.status(at: clock.now), .running(remaining: 2_700))
    }

    func testReconciliationPausesWhenNotificationsAreDisabled() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = TestNotifications()
        await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        clock.now.addTimeInterval(900)
        notifications.notificationsEnabled = false
        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)

        await restoredModel.perform(.reconcile)

        XCTAssertEqual(restoredModel.status(at: clock.now), .paused(remaining: 2_700))
        XCTAssertEqual(restoredModel.issue, .notificationsDisabled)
        XCTAssertFalse(notifications.isReminderPending)
    }

    func testActionsAreIgnoredUntilReconciliationFinishes() async throws {
        let clock = TestClock()
        let notifications = TestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)
        await model.perform(.toggle)
        notifications.isReminderPending = false

        let entered = AsyncStream.makeStream(of: Void.self)
        var continuation: CheckedContinuation<Void, Never>?
        notifications.beforeOperation = {
            guard continuation == nil else { return }
            await withCheckedContinuation {
                continuation = $0
                entered.continuation.yield()
            }
        }
        let reconciliation = Task { await model.perform(.reconcile) }
        for await _ in entered.stream {
            break
        }
        let resume = try XCTUnwrap(continuation)
        XCTAssertTrue(model.isScheduling)

        for action: BreakReminderModel.Action in [.toggle, .restart, .setInterval(.twoHours), .reconcile] {
            await model.perform(action)
        }
        XCTAssertTrue(model.isScheduling)
        XCTAssertEqual(model.interval, .oneHour)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(notifications.cancellationCount, 0)

        resume.resume()
        await reconciliation.value
        XCTAssertFalse(model.isScheduling)
        XCTAssertEqual(model.status(at: clock.now), .running(remaining: 3_600))
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 3_600])
    }

    func testTimeTextUsesHoursOnlyWhenNeeded() {
        XCTAssertEqual(breakReminderTimeText(.paused(remaining: 7_200)), "2:00:00")
        XCTAssertEqual(breakReminderTimeText(.running(remaining: 3_599.1)), "1:00:00")
        XCTAssertEqual(breakReminderTimeText(.running(remaining: 3_599)), "59:59")
        XCTAssertEqual(breakReminderTimeText(.expired), "00:00")
    }

    private func makeModel(
        defaults: UserDefaults,
        clock: TestClock = TestClock(),
        notifications: TestNotifications = TestNotifications()
    ) -> BreakReminderModel {
        BreakReminderModel(notifications: notifications, defaults: defaults, now: { clock.now })
    }
}

@MainActor
private final class TestNotifications: BreakReminderNotifications {
    var beforeOperation: (() async -> Void)?
    var schedulingIssue: BreakReminderIssue?
    var scheduledDurations: [TimeInterval] = []
    var cancellationCount = 0
    var notificationsEnabled = true
    var isReminderPending = false

    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) {
        await beforeOperation?()
        guard notificationsEnabled else {
            throw .notificationsDisabled
        }
        if let schedulingIssue {
            throw schedulingIssue
        }
        scheduledDurations.append(duration)
        isReminderPending = true
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
