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
        defaults: UserDefaults,
        now: @escaping @MainActor () -> Date
    ) {
        self.notifications = notifications
        storage = PersistedValue(key: "break-reminder-state", defaults: defaults)
        self.now = now
        let stored = storage.load()
        countdown = if let stored, stored.isValid(at: now()) { stored } else { .initial }
    }

    /// returns the issue this action ran into; a dropped or unchanged action has none.
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

    /// syncs the system notification with the countdown; an expired countdown keeps its reminder, whose trigger can lag the deadline after sleep or a clock change.
    func reconcile() async {
        await unlessBusy {
            switch countdown.status(at: now()) {
            case .paused:
                notifications.cancel()
            case .expired:
                break
            case .running:
                guard !(await notifications.hasPendingReminder()),
                    case .running(let remaining) = countdown.status(at: now())
                else {
                    return
                }
                await apply(.run(countdown.interval, for: remaining))
            }
        }
    }

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
            // start counting after scheduling returns so an authorization prompt cannot shorten the countdown.
            countdown = .scheduled(interval: interval, deadline: now().addingTimeInterval(duration))
            issue = nil
        case .pause(let interval, let remaining):
            notifications.cancel()
            countdown = .paused(interval: interval, remaining: remaining)
        }
        return nil
    }
}
