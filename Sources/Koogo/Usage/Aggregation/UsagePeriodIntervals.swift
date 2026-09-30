import Foundation

struct UsagePeriodIntervals: Equatable, Sendable {
    let today: Date
    let yesterday: Date
    let last7DaysStart: Date
    let last30Days: Range<Date>
    let previous30Days: Range<Date>
    private let last30DayStarts: [Date]

    var historyStart: Date {
        previous30Days.lowerBound
    }

    init(containing date: Date, calendar: Calendar) {
        guard let todayInterval = calendar.dateInterval(of: .day, for: date) else {
            preconditionFailure("calendar must provide day intervals")
        }
        let dayStartsNewestFirst = Array(
            sequence(first: todayInterval.start) { calendar.startOfDay(for: $0.addingTimeInterval(-1)) }
                .prefix(60)
        )

        today = dayStartsNewestFirst[0]
        yesterday = dayStartsNewestFirst[1]
        last7DaysStart = dayStartsNewestFirst[6]
        last30Days = dayStartsNewestFirst[29]..<todayInterval.end
        previous30Days = dayStartsNewestFirst[59]..<dayStartsNewestFirst[29]
        last30DayStarts = Array(dayStartsNewestFirst.prefix(30))
    }

    func last30Day(containing date: Date) -> Date? {
        guard last30Days.contains(date) else {
            return nil
        }
        return last30DayStarts.first { $0 <= date }
    }
}
