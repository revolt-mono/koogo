import Foundation
import Observation

@MainActor
protocol BreakReminderNotifications: AnyObject {
    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue)
    func isPending() async -> Bool
    func cancel()
}

@MainActor
@Observable
final class BreakReminderModel {
    private let notifications: any BreakReminderNotifications
    private let storage: PersistedValue<BreakReminderCountdown>
    private let now: @MainActor () -> Date

    private(set) var countdown: BreakReminderCountdown {
        didSet { storage.save(countdown) }
    }

    private(set) var isBusy = false

    var status: BreakReminderStatus {
        countdown.status(at: now())
    }

    init(
        notifications: any BreakReminderNotifications,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.notifications = notifications
        storage = PersistedValue(key: "break-reminder-state", defaults: defaults)
        self.now = now
        let stored = storage.load()
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
