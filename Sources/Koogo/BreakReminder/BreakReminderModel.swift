import Foundation
import Observation

@MainActor
protocol BreakReminderNotifications {
    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue)
    func hasPendingReminder() async -> Bool
    func cancel()
}

/// app-scoped; reconciled by the app at launch and by the panel control on each opening.
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

    /// retains the last scheduling failure until scheduling succeeds, including across panel openings.
    private(set) var issue: BreakReminderIssue?

    init(
        notifications: any BreakReminderNotifications,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.notifications = notifications
        storage = PersistedValue(key: "break-reminder-state", defaults: defaults)
        self.now = now
        let stored = storage.load()
        countdown = if let stored, stored.isValid(at: now()) { stored } else { .initial }
    }

    /// drops actions while another change is in flight.
    func perform(_ action: BreakReminderCountdown.Action) async {
        await whileBusy {
            if let change = countdown.change(for: action, at: now()) {
                await apply(change)
            }
        }
    }

    /// reschedules a missing system notification for a running countdown, including after relaunch.
    func reconcile() async {
        await whileBusy {
            guard case .running = countdown.status(at: now()),
                !(await notifications.hasPendingReminder()),
                case .running(let remaining) = countdown.status(at: now())
            else {
                return
            }
            await apply(.run(countdown.interval, for: remaining))
        }
    }

    private func whileBusy(_ work: () async -> Void) async {
        guard !isBusy else {
            return
        }
        isBusy = true
        defer {
            isBusy = false
        }
        await work()
    }

    private func apply(_ change: BreakReminderCountdown.Change) async {
        switch change {
        case .run(let interval, let duration):
            do {
                try await notifications.schedule(after: duration)
            } catch {
                notifications.cancel()
                countdown = .paused(interval: interval, remaining: duration)
                issue = error
                return
            }
            // start counting after scheduling returns so an authorization prompt cannot shorten the countdown.
            countdown = .scheduled(interval: interval, deadline: now().addingTimeInterval(duration))
            issue = nil
        case .pause(let interval, let remaining):
            notifications.cancel()
            countdown = .paused(interval: interval, remaining: remaining)
        }
    }
}
