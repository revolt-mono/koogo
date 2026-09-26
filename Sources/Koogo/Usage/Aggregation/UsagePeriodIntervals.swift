import Foundation

struct UsagePeriodIntervals: Equatable, Sendable {
    struct Comparison: Equatable, Sendable {
        let current: Range<Date>
        let previous: Range<Date>

        fileprivate init(
            component: Calendar.Component,
            containing date: Date,
            calendar: Calendar
        ) {
            guard
                let current = calendar.dateInterval(of: component, for: date),
                let previousDate = calendar.date(byAdding: component, value: -1, to: current.start),
                let previous = calendar.dateInterval(of: component, for: previousDate)
            else {
                preconditionFailure("calendar must provide current and previous period intervals")
            }

            self.current = current.start..<current.end
            self.previous = previous.start..<previous.end
        }
    }

    let day: Comparison
    let week: Range<Date>
    let month: Comparison
    /// The start of each day in the current month, ascending, as the calendar that shaped these periods has it.
    private let currentMonthDays: [Date]

    var historyStart: Date {
        month.previous.lowerBound
    }

    init(containing date: Date, calendar: Calendar) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            preconditionFailure("calendar must provide a week interval")
        }

        let month = Comparison(component: .month, containing: date, calendar: calendar)
        day = Comparison(component: .day, containing: date, calendar: calendar)
        self.week = week.start..<week.end
        self.month = month
        currentMonthDays = Array(
            sequence(first: month.current.lowerBound) { dayStart in
                guard let nextDay = calendar.dateInterval(of: .day, for: dayStart)?.end else {
                    preconditionFailure("calendar must provide day intervals")
                }
                return nextDay
            }
            .prefix { $0 < month.current.upperBound }
        )
    }

    /// The start of the current-month day holding `date`, or nil for a date outside the current month.
    func currentMonthDay(containing date: Date) -> Date? {
        guard month.current.contains(date) else {
            return nil
        }
        return currentMonthDays.last { $0 <= date }
    }
}
