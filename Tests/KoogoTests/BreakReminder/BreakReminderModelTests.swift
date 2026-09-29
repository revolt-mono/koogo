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

            XCTAssertEqual(model.countdown, .paused(interval: .oneHour, remaining: 3_600))
        }
    }

    func testNotificationMirrorsTheCountdown() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        _ = await model.perform(.toggle)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(model.countdown.status(at: clock.now), .running(remaining: 3_600))

        clock.now.addTimeInterval(900)
        _ = await model.perform(.toggle)
        XCTAssertEqual(notifications.cancellationCount, 1)
        XCTAssertFalse(notifications.isReminderPending)
        XCTAssertEqual(model.countdown, .paused(interval: .oneHour, remaining: 2_700))

        _ = await model.perform(.setInterval(.oneHour))
        XCTAssertEqual(notifications.cancellationCount, 1)

        _ = await model.perform(.setInterval(.twoHours))
        _ = await model.perform(.toggle)
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 7_200])
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testDeadlineStartsWhenSchedulingReturns() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        // Stands in for an authorization prompt that stays open for 30 seconds.
        notifications.beforeOperation = { clock.now.addTimeInterval(30) }
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        _ = await model.perform(.toggle)

        XCTAssertEqual(model.countdown.status(at: clock.now), .running(remaining: 3_600))
    }

    func testSchedulingIssuesKeepReminderPausedAndReachTheCaller() async throws {
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), notifications: notifications)

        for issue in [BreakReminderIssue.notificationsDisabled, .schedulingFailed] {
            notifications.schedulingIssue = issue

            let reported = await model.perform(.toggle)

            XCTAssertEqual(reported, issue)
            XCTAssertEqual(model.countdown, .paused(interval: .oneHour, remaining: 3_600))
        }

        XCTAssertTrue(notifications.scheduledDurations.isEmpty)
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testStatePersistsAcrossModelInstances() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let model = makeModel(defaults: defaults, clock: clock)
        _ = await model.perform(.setInterval(.twoHours))
        _ = await model.perform(.toggle)
        clock.now.addTimeInterval(900)

        let restoredModel = makeModel(defaults: defaults, clock: clock)

        XCTAssertEqual(restoredModel.countdown, model.countdown)
        XCTAssertEqual(restoredModel.countdown.status(at: clock.now), .running(remaining: 6_300))

        _ = await restoredModel.perform(.toggle)

        XCTAssertEqual(
            makeModel(defaults: defaults, clock: clock).countdown,
            .paused(interval: .twoHours, remaining: 6_300)
        )
    }

    func testReconciliationKeepsExistingAndRestoresMissingSystemNotification() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        _ = await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
        _ = await restoredModel.reconcile()
        XCTAssertEqual(notifications.scheduledDurations, [3_600])

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        _ = await restoredModel.reconcile()

        XCTAssertTrue(notifications.isReminderPending)
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 2_700])
        XCTAssertEqual(restoredModel.countdown.status(at: clock.now), .running(remaining: 2_700))
    }

    func testReconciliationLeavesPausedAndExpiredCountdownsAlone() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        _ = await model.reconcile()

        _ = await model.perform(.toggle)
        clock.now.addTimeInterval(3_600)
        notifications.isReminderPending = false
        _ = await model.reconcile()

        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(model.countdown.status(at: clock.now), .expired)
    }

    func testReconciliationPausesWhenNotificationsAreDisabled() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        _ = await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        notifications.schedulingIssue = .notificationsDisabled
        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)

        let issue = await restoredModel.reconcile()

        XCTAssertEqual(issue, .notificationsDisabled)
        XCTAssertEqual(restoredModel.countdown, .paused(interval: .oneHour, remaining: 2_700))
        XCTAssertFalse(notifications.isReminderPending)
    }

    func testIntentsAreDroppedWhileANotificationChangeIsInFlight() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)
        _ = await model.perform(.toggle)
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
        let reconciliation = Task { await model.reconcile() }
        for await _ in entered.stream {
            break
        }
        let resume = try XCTUnwrap(continuation)
        XCTAssertTrue(model.isBusy)

        for action: BreakReminderCountdown.Action in [.toggle, .restart, .setInterval(.twoHours)] {
            let dropped = await model.perform(action)
            XCTAssertNil(dropped)
        }
        let droppedReconcile = await model.reconcile()
        XCTAssertNil(droppedReconcile)
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.countdown.interval, .oneHour)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(notifications.cancellationCount, 0)

        resume.resume()
        let reconciled = await reconciliation.value
        XCTAssertNil(reconciled)
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(model.countdown.status(at: clock.now), .running(remaining: 3_600))
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 3_600])
    }

    private func makeModel(
        defaults: UserDefaults,
        clock: TestClock = TestClock(),
        notifications: BreakReminderTestNotifications = BreakReminderTestNotifications()
    ) -> BreakReminderModel {
        BreakReminderModel(notifications: notifications, defaults: defaults, now: { clock.now })
    }
}
