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

/// day bounds in seconds since the reference date, so per-event lookups skip resilient date comparisons.
struct UsagePeriodIntervals: Sendable {
  init(containing date: Date, calendar: Calendar) {
    guard let todayInterval = calendar.dateInterval(of: .day, for: date) else {
      preconditionFailure("calendar must provide day intervals")
    }
    dayStarts = sequence(first: todayInterval.start) { calendar.startOfDay(for: $0.addingTimeInterval(-1)) }
      .prefix(UsagePeriod.last30Days.dayCount)
      .map(\.timeIntervalSinceReferenceDate)
    end = todayInterval.end.timeIntervalSinceReferenceDate
  }

  var last30Days: Range<Date> {
    Date(timeIntervalSinceReferenceDate: dayStarts[dayStarts.count - 1])..<Date(timeIntervalSinceReferenceDate: end)
  }

  var last30DayStarts: [Date] {
    dayStarts.map(Date.init(timeIntervalSinceReferenceDate:))
  }

  func last30DayIndex(containing date: Date) -> Int? {
    let seconds = date.timeIntervalSinceReferenceDate
    return seconds < end ? dayStarts.firstIndex { $0 <= seconds } : nil
  }

  /// local midnights, newest first.
  private let dayStarts: [TimeInterval]
  private let end: TimeInterval
}
