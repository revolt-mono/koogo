import Foundation
import Observation

/// app-scoped; reconciled by the app at launch and by the panel control on each opening.
@MainActor
@Observable
final class BreakReminderModel {
  init(
    notifications: any BreakReminderNotifications,
    defaults: UserDefaults,
    now: @escaping @MainActor () -> Date,
  ) {
    self.notifications = notifications
    storage = PersistedValue(key: "break-reminder-state", defaults: defaults)
    self.now = now
    let stored = storage.load()
    countdown =
      if let stored, stored.isValid(at: now()) {
        stored
      } else {
        .initial
      }
  }

  private(set) var isBusy = false

  private(set) var issue: BreakReminderIssue?

  private(set) var countdown: BreakReminderCountdown {
    didSet { storage.save(countdown) }
  }

  @discardableResult
  func perform(_ action: BreakReminderCountdown.Action) async -> BreakReminderIssue? {
    var raised: BreakReminderIssue?
    await unlessBusy {
      if let change = countdown.change(for: action, at: now()) {
        raised = await apply(change)
      }
    }
    return raised
  }

  /// the notification trigger can lag the countdown deadline after sleep or a clock change.
  func reconcile() async {
    await unlessBusy {
      switch countdown.status(at: now()) {
      case .paused:
        notifications.cancel()
      case .expired:
        break
      case .running:
        guard
          await !notifications.hasPendingReminder(),
          case .running(let remaining) = countdown.status(at: now())
        else {
          return
        }
        await apply(.run(countdown.interval, for: remaining))
      }
    }
  }

  private let notifications: any BreakReminderNotifications
  private let storage: PersistedValue<BreakReminderCountdown>
  private let now: @MainActor () -> Date

  private func unlessBusy(_ work: () async -> Void) async {
    guard !isBusy else {
      return
    }
    isBusy = true
    defer {
      isBusy = false
    }
    await work()
  }

  @discardableResult
  private func apply(_ change: BreakReminderCountdown.Change) async -> BreakReminderIssue? {
    switch change {
    case .run(let interval, let duration):
      do {
        try await notifications.schedule(after: duration)
      } catch {
        notifications.cancel()
        countdown = .paused(interval: interval, remaining: duration)
        issue = error
        return error
      }
      // an authorization prompt must not shorten the countdown.
      countdown = .scheduled(interval: interval, deadline: now().addingTimeInterval(duration))
      issue = nil

    case .pause(let interval, let remaining):
      notifications.cancel()
      countdown = .paused(interval: interval, remaining: remaining)
    }
    return nil
  }
}
