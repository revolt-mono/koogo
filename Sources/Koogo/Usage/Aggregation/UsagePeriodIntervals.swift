import Foundation

struct UsagePeriodIntervals: Sendable {
    struct Comparison: Sendable {
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

    var historyStart: Date {
        month.previous.lowerBound
    }

    init(containing date: Date, calendar: Calendar) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            preconditionFailure("calendar must provide a week interval")
        }

        day = Comparison(component: .day, containing: date, calendar: calendar)
        self.week = week.start..<week.end
        month = Comparison(component: .month, containing: date, calendar: calendar)
    }
}
