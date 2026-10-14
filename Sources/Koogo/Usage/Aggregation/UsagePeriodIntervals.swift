import Foundation

enum UsagePeriod: String, CaseIterable, Sendable, Encodable, CodingKeyRepresentable {
    case today
    case last7Days
    case last30Days

    var dayCount: Int {
        switch self {
        case .today: 1
        case .last7Days: 7
        case .last30Days: 30
        }
    }
}

struct UsagePeriodIntervals: Equatable, Sendable {
    let last30Days: Range<Date>
    let last30DayStarts: [Date]

    init(containing date: Date, calendar: Calendar) {
        guard let todayInterval = calendar.dateInterval(of: .day, for: date) else {
            preconditionFailure("calendar must provide day intervals")
        }
        let dayCount = UsagePeriod.last30Days.dayCount
        last30DayStarts = Array(
            sequence(first: todayInterval.start) { calendar.startOfDay(for: $0.addingTimeInterval(-1)) }
                .prefix(dayCount)
        )
        last30Days = last30DayStarts[dayCount - 1]..<todayInterval.end
    }

    func last30DayIndex(containing date: Date) -> Int? {
        guard last30Days.contains(date) else {
            return nil
        }
        return last30DayStarts.firstIndex { $0 <= date }
    }
}
