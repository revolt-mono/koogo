import Foundation
import Observation

@MainActor
protocol BreakReminderNotifications {
    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue)
    func hasPendingReminder() async -> Bool
    func cancel()
}

/// Lives for the app. `KoogoApp` reconciles once at launch and the panel control again each time the panel opens.
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

    /// Why the last schedule failed. Stays until a schedule succeeds, so a failure at launch is still shown when the panel opens.
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

    /// Dropped while another change is in flight.
    func perform(_ action: BreakReminderCountdown.Action) async {
        await whileBusy {
            if let change = countdown.change(for: action, at: now()) {
                await apply(change)
            }
        }
    }

    /// Reschedules the system notification a running countdown has lost, such as after a relaunch.
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
            // Measured once scheduling returns, so an authorization prompt doesn't shorten the countdown.
            countdown = .scheduled(interval: interval, deadline: now().addingTimeInterval(duration))
            issue = nil
        case .pause(let interval, let remaining):
            notifications.cancel()
            countdown = .paused(interval: interval, remaining: remaining)
        }
    }
}
