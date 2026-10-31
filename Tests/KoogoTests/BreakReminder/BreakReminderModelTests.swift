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

        await model.perform(.toggle)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(model.countdown.status(at: clock.now), .running(remaining: 3_600))

        clock.now.addTimeInterval(900)
        await model.perform(.toggle)
        XCTAssertEqual(notifications.cancellationCount, 1)
        XCTAssertFalse(notifications.isReminderPending)
        XCTAssertEqual(model.countdown, .paused(interval: .oneHour, remaining: 2_700))

        await model.perform(.setInterval(.oneHour))
        XCTAssertEqual(notifications.cancellationCount, 1)

        await model.perform(.setInterval(.twoHours))
        await model.perform(.toggle)
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 7_200])
        XCTAssertEqual(notifications.cancellationCount, 2)
    }

    func testDeadlineStartsWhenSchedulingReturns() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        notifications.beforeOperation = { clock.now.addTimeInterval(30) }
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        await model.perform(.toggle)

        XCTAssertEqual(model.countdown.status(at: clock.now), .running(remaining: 3_600))
    }

    func testSchedulingIssuesKeepReminderPausedAndShowUntilAScheduleSucceeds() async throws {
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), notifications: notifications)

        for issue in [BreakReminderIssue.notificationsDisabled, .schedulingFailed] {
            notifications.schedulingIssue = issue

            let raised = await model.perform(.toggle)

            XCTAssertEqual(raised, issue)
            XCTAssertEqual(model.issue, issue)
            XCTAssertEqual(model.countdown, .paused(interval: .oneHour, remaining: 3_600))
        }
        XCTAssertTrue(notifications.scheduledDurations.isEmpty)
        XCTAssertEqual(notifications.cancellationCount, 2)

        await model.perform(.setInterval(.twoHours))
        XCTAssertEqual(model.issue, .schedulingFailed)

        notifications.schedulingIssue = nil
        await model.perform(.toggle)
        XCTAssertNil(model.issue)
        XCTAssertEqual(notifications.scheduledDurations, [7_200])
    }

    func testStatePersistsAcrossModelInstances() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let model = makeModel(defaults: defaults, clock: clock)
        await model.perform(.setInterval(.twoHours))
        await model.perform(.toggle)
        clock.now.addTimeInterval(900)

        let restoredModel = makeModel(defaults: defaults, clock: clock)

        XCTAssertEqual(restoredModel.countdown, model.countdown)
        XCTAssertEqual(restoredModel.countdown.status(at: clock.now), .running(remaining: 6_300))

        await restoredModel.perform(.toggle)

        XCTAssertEqual(
            makeModel(defaults: defaults, clock: clock).countdown,
            .paused(interval: .twoHours, remaining: 6_300)
        )
    }

    func testReconciliationKeepsExistingAndRestoresMissingSystemNotification() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
        await restoredModel.reconcile()
        XCTAssertEqual(notifications.scheduledDurations, [3_600])

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        await restoredModel.reconcile()

        XCTAssertTrue(notifications.isReminderPending)
        XCTAssertEqual(notifications.scheduledDurations, [3_600, 2_700])
        XCTAssertEqual(restoredModel.countdown.status(at: clock.now), .running(remaining: 2_700))
    }

    func testReconciliationLeavesPausedAndExpiredCountdownsAlone() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)

        await model.reconcile()

        await model.perform(.toggle)
        clock.now.addTimeInterval(3_600)
        notifications.isReminderPending = false
        await model.reconcile()

        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(model.countdown.status(at: clock.now), .expired)
    }

    func testReconciliationKeepsTheReminderOfAnExpiredCountdown() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        let model = makeModel(defaults: try makeIsolatedDefaults(), clock: clock, notifications: notifications)
        await model.perform(.toggle)

        clock.now.addTimeInterval(3_601)
        await model.reconcile()

        XCTAssertTrue(notifications.isReminderPending)
    }

    func testReconciliationCancelsTheReminderOfADiscardedCountdown() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        clock.now.addTimeInterval(-3_600)
        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
        XCTAssertEqual(restoredModel.countdown, .initial)
        await restoredModel.reconcile()

        XCTAssertFalse(notifications.isReminderPending)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
    }

    func testReconciliationPausesWhenNotificationsAreDisabled() async throws {
        let defaults = try makeIsolatedDefaults()
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
        await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

        clock.now.addTimeInterval(900)
        notifications.isReminderPending = false
        notifications.schedulingIssue = .notificationsDisabled
        let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)

        await restoredModel.reconcile()

        XCTAssertEqual(restoredModel.issue, .notificationsDisabled)
        XCTAssertEqual(restoredModel.countdown, .paused(interval: .oneHour, remaining: 2_700))
        XCTAssertFalse(notifications.isReminderPending)

        notifications.schedulingIssue = nil
        await restoredModel.reconcile()
        XCTAssertEqual(restoredModel.issue, .notificationsDisabled)
        XCTAssertEqual(restoredModel.countdown, .paused(interval: .oneHour, remaining: 2_700))
    }

    func testIntentsAreDroppedWhileANotificationChangeIsInFlight() async throws {
        let clock = TestClock()
        let notifications = BreakReminderTestNotifications()
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
        let reconciliation = Task { await model.reconcile() }
        for await _ in entered.stream {
            break
        }
        let resume = try XCTUnwrap(continuation)
        XCTAssertTrue(model.isBusy)

        notifications.schedulingIssue = .notificationsDisabled
        for action: BreakReminderCountdown.Action in [.toggle, .restart, .setInterval(.twoHours)] {
            let raised = await model.perform(action)
            XCTAssertNil(raised)
        }
        notifications.schedulingIssue = nil
        await model.reconcile()
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.countdown.interval, .oneHour)
        XCTAssertEqual(notifications.scheduledDurations, [3_600])
        XCTAssertEqual(notifications.cancellationCount, 0)

        resume.resume()
        await reconciliation.value
        XCTAssertNil(model.issue)
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
