import Foundation
import Observation

enum BreakReminderInterval: Int, CaseIterable, Codable {
    case oneHour = 60
    case ninetyMinutes = 90
    case twoHours = 120

    var duration: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

enum BreakReminderStatus: Equatable {
    case running(remaining: TimeInterval)
    case paused(remaining: TimeInterval)
    case expired
}

enum BreakReminderIssue: Error, Equatable {
    case notificationsDisabled
    case schedulingFailed

    var title: String {
        switch self {
        case .notificationsDisabled:
            "Notifications Are Off"
        case .schedulingFailed:
            "Couldn't Start Break Reminder"
        }
    }

    var message: String {
        switch self {
        case .notificationsDisabled:
            "Allow Koogo notifications in System Settings before starting the break reminder."
        case .schedulingFailed:
            "Koogo couldn't schedule the notification. Please try again."
        }
    }
}

@MainActor
protocol BreakReminderNotifications: AnyObject {
    func schedule(after duration: TimeInterval) async throws(BreakReminderIssue) -> Date
    func hasDeliverableReminder() async -> Bool
    func cancel()
}

@MainActor
@Observable
final class BreakReminderModel {
    enum Action {
        case toggle
        case restart
        case setInterval(BreakReminderInterval)
        case reconcile
    }

    private enum Countdown: Codable {
        case scheduled(interval: BreakReminderInterval, deadline: Date)
        case paused(interval: BreakReminderInterval, remaining: TimeInterval)

        var isValid: Bool {
            switch self {
            case .scheduled(_, let deadline):
                deadline.timeIntervalSinceReferenceDate.isFinite
            case .paused(let interval, let remaining):
                remaining > 0 && remaining <= interval.duration
            }
        }
    }

    private static let defaultsKey = "break-reminder-state"

    private let notifications: any BreakReminderNotifications
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private var countdown: Countdown

    var interval: BreakReminderInterval {
        switch countdown {
        case .scheduled(let interval, _), .paused(let interval, _):
            interval
        }
    }

    private(set) var issue: BreakReminderIssue?
    private(set) var isScheduling = false

    init(
        notifications: any BreakReminderNotifications,
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.notifications = notifications
        self.defaults = defaults
        self.now = now

        if let data = defaults.data(forKey: Self.defaultsKey),
            let countdown = try? PropertyListDecoder().decode(Countdown.self, from: data),
            countdown.isValid
        {
            self.countdown = countdown
        } else {
            countdown = .paused(interval: .oneHour, remaining: BreakReminderInterval.oneHour.duration)
        }
    }

    func status(at date: Date) -> BreakReminderStatus {
        switch countdown {
        case .scheduled(_, let deadline):
            deadline > date
                ? .running(remaining: deadline.timeIntervalSince(date))
                : .expired
        case .paused(_, let remaining):
            .paused(remaining: remaining)
        }
    }

    func perform(_ action: Action) async {
        guard !isScheduling else {
            return
        }
        isScheduling = true
        defer {
            isScheduling = false
        }

        switch (action, status(at: now())) {
        case (.toggle, .running(let remaining)):
            pause(interval: interval, remaining: remaining)
        case (.toggle, .paused(let remaining)):
            await start(interval: interval, after: remaining)
        case (.toggle, .expired), (.restart, _):
            await start(interval: interval, after: interval.duration)
        case (.setInterval(let newInterval), let status):
            guard newInterval != interval else {
                return
            }
            if case .running = status {
                await start(interval: newInterval, after: newInterval.duration)
            } else {
                pause(interval: newInterval, remaining: newInterval.duration)
            }
        case (.reconcile, .running):
            guard !(await notifications.hasDeliverableReminder()),
                case .running(let remaining) = status(at: now())
            else {
                return
            }
            await start(interval: interval, after: remaining)
        case (.reconcile, .paused), (.reconcile, .expired):
            break
        }
    }

    func dismissIssue() {
        issue = nil
    }

    private func start(interval: BreakReminderInterval, after duration: TimeInterval) async {
        issue = nil
        do {
            let deadline = try await notifications.schedule(after: duration)
            countdown = .scheduled(interval: interval, deadline: deadline)
            persist()
        } catch {
            pause(interval: interval, remaining: duration, issue: error)
        }
    }

    private func pause(
        interval: BreakReminderInterval,
        remaining: TimeInterval,
        issue: BreakReminderIssue? = nil
    ) {
        countdown = .paused(interval: interval, remaining: remaining)
        notifications.cancel()
        self.issue = issue
        persist()
    }

    private func persist() {
        guard let data = try? PropertyListEncoder().encode(countdown) else {
            return
        }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
