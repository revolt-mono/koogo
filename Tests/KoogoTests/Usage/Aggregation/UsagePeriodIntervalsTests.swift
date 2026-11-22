import Foundation
import Testing

@testable import Koogo

struct UsagePeriodIntervalsTests {
  @Test
  func `rolling periods use local midnights across month boundaries`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let date = try Date("2026-03-11T12:00:00Z", strategy: .iso8601)
    let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

    try #expect(intervals.last30DayStarts[0] == Date("2026-03-11T07:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30DayStarts[1] == Date("2026-03-10T07:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30DayStarts[6] == Date("2026-03-05T08:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30Days.lowerBound.date == Date("2026-02-10T08:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30Days.upperBound.date == Date("2026-03-12T07:00:00Z", strategy: .iso8601))
    #expect(intervals.last30DayIndex(containing: UsageTimestamp(date)) == 0)
  }

  @Test
  func `midnight daylight saving transition keeps previous day whole`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Havana"))
    let date = try Date("2026-03-08T12:00:00Z", strategy: .iso8601)
    let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

    try #expect(intervals.last30DayStarts[0] == Date("2026-03-08T05:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30Days.upperBound.date == Date("2026-03-09T04:00:00Z", strategy: .iso8601))
    try #expect(intervals.last30DayStarts[1] == Date("2026-03-07T05:00:00Z", strategy: .iso8601))
  }

  @Test
  func `daily buckets follow midnight across daylight saving time`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    for (start, end) in [
      ("2026-03-08T08:00:00Z", "2026-03-09T07:00:00Z"),
      ("2026-11-01T07:00:00Z", "2026-11-02T08:00:00Z"),
    ] {
      let midnight = try Date(start, strategy: .iso8601)
      let nextMidnight = try Date(end, strategy: .iso8601)
      let intervals = UsagePeriodIntervals(containing: midnight, calendar: calendar)

      #expect(intervals.last30DayStarts[0] == midnight)
      #expect(intervals.last30Days.upperBound.date == nextMidnight)
      #expect(intervals.last30DayIndex(containing: UsageTimestamp(midnight)) == 0)
      #expect(intervals.last30DayIndex(containing: UsageTimestamp(nextMidnight.addingTimeInterval(-0.001))) == 0)
      #expect(intervals.last30DayIndex(containing: UsageTimestamp(nextMidnight)) == nil)
      #expect(intervals.last30DayIndex(containing: intervals.last30Days.lowerBound) == 29)
      #expect(
        intervals.last30DayIndex(containing: UsageTimestamp(intervals.last30Days.lowerBound.date.addingTimeInterval(-0.001)))
          == nil
      )
    }
  }
}
