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

struct UsagePeriodIntervals: Sendable {
  init(containing date: Date, calendar: Calendar) {
    guard let todayInterval = calendar.dateInterval(of: .day, for: date) else {
      preconditionFailure("calendar must provide day intervals")
    }
    dayStarts = sequence(first: todayInterval.start) { calendar.startOfDay(for: $0.addingTimeInterval(-1)) }
      .prefix(UsagePeriod.last30Days.dayCount)
      .map(UsageTimestamp.init)
    end = UsageTimestamp(todayInterval.end)
  }

  var last30Days: Range<UsageTimestamp> {
    dayStarts[dayStarts.count - 1]..<end
  }

  var last30DayStarts: [Date] {
    dayStarts.map(\.date)
  }

  func last30DayIndex(containing timestamp: UsageTimestamp) -> Int? {
    timestamp < end ? dayStarts.firstIndex { $0 <= timestamp } : nil
  }

  private let dayStarts: [UsageTimestamp]
  private let end: UsageTimestamp
}
