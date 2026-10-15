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

    var timeText: String {
        let remaining: TimeInterval =
            switch self {
            case .running(let value), .paused(let value): value
            case .expired: 0
            }

        let whole = Duration.seconds(ceil(remaining))
        return whole.formatted(
            .displayTime(pattern: whole >= .seconds(3_600) ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2))
        )
    }
}

enum BreakReminderIssue: Error {
    case notificationsDisabled
    case schedulingFailed
}

enum BreakReminderCountdown: Codable, Equatable {
    case scheduled(interval: BreakReminderInterval, deadline: Date)
    case paused(interval: BreakReminderInterval, remaining: TimeInterval)

    enum Action {
        case toggle
        case restart
        case setInterval(BreakReminderInterval)
    }

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

    /// A stored countdown is usable when its remaining time fits in its interval.
    func isValid(at date: Date) -> Bool {
        switch self {
        case .scheduled(let interval, let deadline):
            deadline.timeIntervalSince(date) <= interval.duration
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
