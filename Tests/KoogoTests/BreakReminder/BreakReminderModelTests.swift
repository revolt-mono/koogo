import Foundation
import Testing

@testable import Koogo

@MainActor
struct BreakReminderModelTests {
  @Test
  func `missing or invalid persisted state falls back to paused hour`() async throws {
    let outOfRangePause = try PropertyListEncoder().encode(
      BreakReminderCountdown.paused(interval: .oneHour, remaining: 9_999)
    )

    for payload in [nil, Data("garbage".utf8), outOfRangePause] {
      let defaults = try scratch.makeIsolatedDefaults()
      await makeModel(defaults: defaults).perform(.setInterval(.twoHours))
      defaults.set(payload, forKey: "break-reminder-state")

      let model = makeModel(defaults: defaults)

      #expect(model.countdown == .paused(interval: .oneHour, remaining: 3_600))
    }
  }

  @Test
  func `countdowns keep their stored shape`() throws {
    let clock = TestClock()
    let deadline = clock.now.addingTimeInterval(600)
    let saved: [(propertyList: [String: Any], countdown: BreakReminderCountdown)] = [
      (["paused": ["interval": 90, "remaining": 1_200.0]], .paused(interval: .ninetyMinutes, remaining: 1_200)),
      (["scheduled": ["interval": 120, "deadline": deadline]], .scheduled(interval: .twoHours, deadline: deadline)),
    ]

    for (propertyList, countdown) in saved {
      let defaults = try scratch.makeIsolatedDefaults()
      let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .binary, options: 0)
      defaults.set(data, forKey: "break-reminder-state")

      #expect(makeModel(defaults: defaults, clock: clock).countdown == countdown)
      let encoded = try PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(countdown), format: nil)
      #expect(encoded as? NSDictionary == propertyList as NSDictionary)
    }
  }

  @Test
  func `notification mirrors the countdown`() async throws {
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), clock: clock, notifications: notifications)

    await model.perform(.toggle)
    #expect(notifications.scheduledDurations == [3_600])
    #expect(model.countdown.status(at: clock.now) == .running(remaining: 3_600))

    clock.now.addTimeInterval(900)
    await model.perform(.toggle)
    #expect(notifications.cancellationCount == 1)
    #expect(!notifications.isReminderPending)
    #expect(model.countdown == .paused(interval: .oneHour, remaining: 2_700))

    await model.perform(.setInterval(.oneHour))
    #expect(notifications.cancellationCount == 1)

    await model.perform(.setInterval(.twoHours))
    await model.perform(.toggle)
    #expect(notifications.scheduledDurations == [3_600, 7_200])
    #expect(notifications.cancellationCount == 2)
  }

  @Test
  func `deadline starts when scheduling returns`() async throws {
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    notifications.beforeOperation = { clock.now.addTimeInterval(30) }
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), clock: clock, notifications: notifications)

    await model.perform(.toggle)

    #expect(model.countdown.status(at: clock.now) == .running(remaining: 3_600))
  }

  @Test
  func `scheduling issues keep reminder paused and show until a schedule succeeds`() async throws {
    let notifications = BreakReminderTestNotifications()
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), notifications: notifications)

    for issue in [BreakReminderIssue.notificationsDeclined, .notificationsBlocked, .schedulingFailed] {
      notifications.schedulingIssue = issue

      let raised = await model.perform(.toggle)

      #expect(raised == issue)
      #expect(model.issue == issue)
      #expect(model.countdown == .paused(interval: .oneHour, remaining: 3_600))
    }
    #expect(notifications.scheduledDurations.isEmpty)
    #expect(notifications.cancellationCount == 3)

    await model.perform(.setInterval(.twoHours))
    #expect(model.issue == .schedulingFailed)

    notifications.schedulingIssue = nil
    await model.perform(.toggle)
    #expect(model.issue == nil)
    #expect(notifications.scheduledDurations == [7_200])
  }

  @Test
  func `state persists across model instances`() async throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let clock = TestClock()
    let model = makeModel(defaults: defaults, clock: clock)
    await model.perform(.setInterval(.twoHours))
    await model.perform(.toggle)
    clock.now.addTimeInterval(900)

    let restoredModel = makeModel(defaults: defaults, clock: clock)

    #expect(restoredModel.countdown == model.countdown)
    #expect(restoredModel.countdown.status(at: clock.now) == .running(remaining: 6_300))

    await restoredModel.perform(.toggle)

    #expect(makeModel(defaults: defaults, clock: clock).countdown == .paused(interval: .twoHours, remaining: 6_300))
  }

  @Test
  func `reconciliation keeps existing and restores missing system notification`() async throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

    let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
    await restoredModel.reconcile()
    #expect(notifications.scheduledDurations == [3_600])

    clock.now.addTimeInterval(900)
    notifications.isReminderPending = false
    await restoredModel.reconcile()

    #expect(notifications.isReminderPending)
    #expect(notifications.scheduledDurations == [3_600, 2_700])
    #expect(restoredModel.countdown.status(at: clock.now) == .running(remaining: 2_700))
  }

  @Test
  func `reconciliation leaves paused and expired countdowns alone`() async throws {
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), clock: clock, notifications: notifications)

    await model.reconcile()

    await model.perform(.toggle)
    clock.now.addTimeInterval(3_600)
    notifications.isReminderPending = false
    await model.reconcile()

    #expect(notifications.scheduledDurations == [3_600])
    #expect(model.countdown.status(at: clock.now) == .expired)
  }

  @Test
  func `reconciliation keeps the reminder of an expired countdown`() async throws {
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), clock: clock, notifications: notifications)
    await model.perform(.toggle)

    clock.now.addTimeInterval(3_601)
    await model.reconcile()

    #expect(notifications.isReminderPending)
  }

  @Test
  func `reconciliation cancels the reminder of a discarded countdown`() async throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

    clock.now.addTimeInterval(-3_600)
    let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)
    #expect(restoredModel.countdown == .initial)
    await restoredModel.reconcile()

    #expect(!notifications.isReminderPending)
    #expect(notifications.scheduledDurations == [3_600])
  }

  @Test
  func `reconciliation pauses when notifications are disabled`() async throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    await makeModel(defaults: defaults, clock: clock, notifications: notifications).perform(.toggle)

    clock.now.addTimeInterval(900)
    notifications.isReminderPending = false
    notifications.schedulingIssue = .notificationsBlocked
    let restoredModel = makeModel(defaults: defaults, clock: clock, notifications: notifications)

    await restoredModel.reconcile()

    #expect(restoredModel.issue == .notificationsBlocked)
    #expect(restoredModel.countdown == .paused(interval: .oneHour, remaining: 2_700))
    #expect(!notifications.isReminderPending)

    notifications.schedulingIssue = nil
    await restoredModel.reconcile()
    #expect(restoredModel.issue == .notificationsBlocked)
    #expect(restoredModel.countdown == .paused(interval: .oneHour, remaining: 2_700))
  }

  @Test
  func `intents are dropped while a notification change is in flight`() async throws {
    let clock = TestClock()
    let notifications = BreakReminderTestNotifications()
    let model = makeModel(defaults: try scratch.makeIsolatedDefaults(), clock: clock, notifications: notifications)
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
    let resume = try #require(continuation)
    #expect(model.isBusy)

    notifications.schedulingIssue = .notificationsBlocked
    for action: BreakReminderCountdown.Action in [.toggle, .restart, .setInterval(.twoHours)] {
      let raised = await model.perform(action)
      #expect(raised == nil)
    }
    notifications.schedulingIssue = nil
    await model.reconcile()
    #expect(model.isBusy)
    #expect(model.countdown.interval == .oneHour)
    #expect(notifications.scheduledDurations == [3_600])
    #expect(notifications.cancellationCount == 0)

    resume.resume()
    await reconciliation.value
    #expect(model.issue == nil)
    #expect(!model.isBusy)
    #expect(model.countdown.status(at: clock.now) == .running(remaining: 3_600))
    #expect(notifications.scheduledDurations == [3_600, 3_600])
  }

  private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000)
  }

  private let scratch = Scratch()

  private func makeModel(
    defaults: UserDefaults,
    clock: TestClock = TestClock(),
    notifications: BreakReminderTestNotifications = BreakReminderTestNotifications(),
  ) -> BreakReminderModel {
    BreakReminderModel(notifications: notifications, defaults: defaults, now: { clock.now })
  }
}
