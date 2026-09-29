import Foundation
import Observation

/// The system notification that mirrors the countdown: pending while it runs, absent while it's paused.
@MainActor
protocol BreakReminderNotifications: AnyObject {
    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue)
    func isPending() async -> Bool
    func cancel()
}

/// Owns the countdown and keeps the system notification in step with it. Every intent returns the
/// issue that stopped it, if any, so the view that asked can show it.
@MainActor
@Observable
final class BreakReminderModel {
    private static let defaultsKey = "break-reminder-state"

    private let notifications: any BreakReminderNotifications
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date

    private(set) var countdown: BreakReminderCountdown {
        didSet {
            guard let data = try? PropertyListEncoder().encode(countdown) else {
                return
            }
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// A notification change is in flight; intents arriving meanwhile are dropped.
    private(set) var isBusy = false

    init(
        notifications: any BreakReminderNotifications,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.notifications = notifications
        self.defaults = defaults
        self.now = now
        let stored = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? PropertyListDecoder().decode(BreakReminderCountdown.self, from: $0) }
        countdown = if let stored, stored.isValid { stored } else { .initial }
    }

    func perform(_ action: BreakReminderCountdown.Action) async -> BreakReminderIssue? {
        await whileBusy {
            guard let change = countdown.change(for: action, at: now()) else {
                return nil
            }
            return await apply(change)
        }
    }

    /// Reschedules the notification of a running countdown that lost it, such as after a relaunch
    /// or once notifications were turned off; the latter pauses the countdown with the issue.
    func reconcile() async -> BreakReminderIssue? {
        await whileBusy {
            guard case .running = countdown.status(at: now()),
                !(await notifications.isPending()),
                case .running(let remaining) = countdown.status(at: now())
            else {
                return nil
            }
            return await apply(.run(countdown.interval, for: remaining))
        }
    }

    private func whileBusy(_ work: () async -> BreakReminderIssue?) async -> BreakReminderIssue? {
        guard !isBusy else {
            return nil
        }
        isBusy = true
        defer {
            isBusy = false
        }
        return await work()
    }

    private func apply(_ change: BreakReminderCountdown.Change) async -> BreakReminderIssue? {
        switch change {
        case .run(let interval, let duration):
            do {
                try await notifications.schedule(after: duration)
            } catch {
                notifications.cancel()
                countdown = .paused(interval: interval, remaining: duration)
                return error
            }
            // Measured once scheduling returns, so an authorization prompt doesn't shorten the countdown.
            countdown = .scheduled(interval: interval, deadline: now().addingTimeInterval(duration))
        case .pause(let interval, let remaining):
            notifications.cancel()
            countdown = .paused(interval: interval, remaining: remaining)
        }
        return nil
    }
}
