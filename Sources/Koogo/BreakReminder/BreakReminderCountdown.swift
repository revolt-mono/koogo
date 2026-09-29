import Foundation

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
}

/// The persisted countdown: the selected interval, and either a deadline it counts toward or the time
/// left while paused. The rules for every user intent live here, free of clocks and notifications.
enum BreakReminderCountdown: Codable, Equatable {
    case scheduled(interval: BreakReminderInterval, deadline: Date)
    case paused(interval: BreakReminderInterval, remaining: TimeInterval)

    enum Action {
        case toggle
        case restart
        case setInterval(BreakReminderInterval)
    }

    /// What the countdown becomes once the system notification matches: pending for `run`, gone for
    /// `pause`. The deadline of a run is measured when scheduling returns, not when it was decided.
    enum Change: Equatable {
        case run(BreakReminderInterval, for: TimeInterval)
        case pause(BreakReminderInterval, remaining: TimeInterval)
    }

    static let initial = Self.paused(interval: .oneHour, remaining: BreakReminderInterval.oneHour.duration)

    var interval: BreakReminderInterval {
        switch self {
        case .scheduled(let interval, _), .paused(let interval, _):
            interval
        }
    }

    /// Rejects a persisted pause outside its interval and a deadline that is not a real date.
    var isValid: Bool {
        switch self {
        case .scheduled(_, let deadline):
            deadline.timeIntervalSinceReferenceDate.isFinite
        case .paused(let interval, let remaining):
            remaining > 0 && remaining <= interval.duration
        }
    }

    func status(at date: Date) -> BreakReminderStatus {
        switch self {
        case .scheduled(_, let deadline):
            deadline > date
                ? .running(remaining: deadline.timeIntervalSince(date))
                : .expired
        case .paused(_, let remaining):
            .paused(remaining: remaining)
        }
    }

    /// The change `action` asks for at `date`, or nil when the countdown is already there.
    func change(for action: Action, at date: Date) -> Change? {
        switch (action, status(at: date)) {
        case (.toggle, .running(let remaining)):
            .pause(interval, remaining: remaining)
        case (.toggle, .paused(let remaining)):
            .run(interval, for: remaining)
        case (.toggle, .expired), (.restart, _):
            .run(interval, for: interval.duration)
        case (.setInterval(let newInterval), _) where newInterval == interval:
            nil
        case (.setInterval(let newInterval), .running):
            .run(newInterval, for: newInterval.duration)
        case (.setInterval(let newInterval), .paused), (.setInterval(let newInterval), .expired):
            .pause(newInterval, remaining: newInterval.duration)
        }
    }
}
