import XCTest

@testable import Koogo

final class UsagePeriodIntervalsTests: XCTestCase {
  func testRollingPeriodsUseLocalMidnightsAcrossMonthBoundaries() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let date = try Date("2026-03-11T12:00:00Z", strategy: .iso8601)
    let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

    XCTAssertEqual(intervals.last30DayStarts[0], try Date("2026-03-11T07:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30DayStarts[1], try Date("2026-03-10T07:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30DayStarts[6], try Date("2026-03-05T08:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30Days.lowerBound.date, try Date("2026-02-10T08:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30Days.upperBound.date, try Date("2026-03-12T07:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30DayIndex(containing: UsageTimestamp(date)), 0)
  }

  func testMidnightDaylightSavingTransitionKeepsPreviousDayWhole() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Havana"))
    let date = try Date("2026-03-08T12:00:00Z", strategy: .iso8601)
    let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

    XCTAssertEqual(intervals.last30DayStarts[0], try Date("2026-03-08T05:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30Days.upperBound.date, try Date("2026-03-09T04:00:00Z", strategy: .iso8601))
    XCTAssertEqual(intervals.last30DayStarts[1], try Date("2026-03-07T05:00:00Z", strategy: .iso8601))
  }

  func testDailyBucketsFollowMidnightAcrossDaylightSavingTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    for (start, end) in [
      ("2026-03-08T08:00:00Z", "2026-03-09T07:00:00Z"),
      ("2026-11-01T07:00:00Z", "2026-11-02T08:00:00Z"),
    ] {
      let midnight = try Date(start, strategy: .iso8601)
      let nextMidnight = try Date(end, strategy: .iso8601)
      let intervals = UsagePeriodIntervals(containing: midnight, calendar: calendar)

      XCTAssertEqual(intervals.last30DayStarts[0], midnight)
      XCTAssertEqual(intervals.last30Days.upperBound.date, nextMidnight)
      XCTAssertEqual(intervals.last30DayIndex(containing: UsageTimestamp(midnight)), 0)
      XCTAssertEqual(intervals.last30DayIndex(containing: UsageTimestamp(nextMidnight.addingTimeInterval(-0.001))), 0)
      XCTAssertNil(intervals.last30DayIndex(containing: UsageTimestamp(nextMidnight)))
      XCTAssertEqual(intervals.last30DayIndex(containing: intervals.last30Days.lowerBound), 29)
      XCTAssertNil(
        intervals.last30DayIndex(containing: UsageTimestamp(intervals.last30Days.lowerBound.date.addingTimeInterval(-0.001)))
      )
    }
  }
}
