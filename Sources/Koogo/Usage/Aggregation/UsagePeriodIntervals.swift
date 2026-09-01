import Foundation

struct UsageInterval: Equatable, Sendable {
    let upperBound: Date
    private let duration: TimeInterval

    var lowerBound: Date {
        upperBound.addingTimeInterval(-duration)
    }

    fileprivate init(duration: TimeInterval, endingAt upperBound: Date) {
        self.upperBound = upperBound
        self.duration = duration
    }

    fileprivate var previous: Self {
        Self(duration: duration, endingAt: lowerBound)
    }

    func contains(_ date: Date) -> Bool {
        date > lowerBound && date <= upperBound
    }
}

struct UsagePeriodIntervals: Equatable, Sendable {
    struct Comparison: Equatable, Sendable {
        let current: UsageInterval
        let previous: UsageInterval

        fileprivate init(current: UsageInterval) {
            self.current = current
            previous = current.previous
        }
    }

    let last24Hours: Comparison
    let last7Days: UsageInterval
    let last30Days: Comparison

    init(endingAt date: Date) {
        last24Hours = Comparison(
            current: UsageInterval(duration: 24 * 60 * 60, endingAt: date)
        )
        last7Days = UsageInterval(duration: 7 * 24 * 60 * 60, endingAt: date)
        last30Days = Comparison(
            current: UsageInterval(duration: 30 * 24 * 60 * 60, endingAt: date)
        )
    }
}
