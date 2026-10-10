import Foundation
import XCTest

@testable import Koogo

final class UsagePeriodIntervalsTests: XCTestCase {
    func testRollingPeriodsUseLocalMidnightsAcrossMonthBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(Date(iso8601: "2026-03-11T12:00:00Z"))
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

        XCTAssertEqual(intervals.last30DayStarts[0], Date(iso8601: "2026-03-11T07:00:00Z"))
        XCTAssertEqual(intervals.last30DayStarts[1], Date(iso8601: "2026-03-10T07:00:00Z"))
        XCTAssertEqual(intervals.last30DayStarts[6], Date(iso8601: "2026-03-05T08:00:00Z"))
        XCTAssertEqual(intervals.last30Days.lowerBound, Date(iso8601: "2026-02-10T08:00:00Z"))
        XCTAssertEqual(intervals.last30Days.upperBound, Date(iso8601: "2026-03-12T07:00:00Z"))
        XCTAssertEqual(intervals.previous30Days.lowerBound, Date(iso8601: "2026-01-11T08:00:00Z"))
        XCTAssertEqual(intervals.previous30Days.upperBound, intervals.last30Days.lowerBound)
        XCTAssertEqual(intervals.historyStart, intervals.previous30Days.lowerBound)
        XCTAssertEqual(intervals.last30DayIndex(containing: date), 0)
    }

    func testMidnightDaylightSavingTransitionKeepsPreviousDayWhole() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Havana"))
        let date = try XCTUnwrap(Date(iso8601: "2026-03-08T12:00:00Z"))
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

        XCTAssertEqual(intervals.last30DayStarts[0], Date(iso8601: "2026-03-08T05:00:00Z"))
        XCTAssertEqual(intervals.last30Days.upperBound, Date(iso8601: "2026-03-09T04:00:00Z"))
        XCTAssertEqual(intervals.last30DayStarts[1], Date(iso8601: "2026-03-07T05:00:00Z"))
    }

    func testDailyBucketsFollowMidnightAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (start, end) in [
            ("2026-03-08T08:00:00Z", "2026-03-09T07:00:00Z"),
            ("2026-11-01T07:00:00Z", "2026-11-02T08:00:00Z"),
        ] {
            let midnight = try XCTUnwrap(Date(iso8601: start))
            let nextMidnight = try XCTUnwrap(Date(iso8601: end))
            let intervals = UsagePeriodIntervals(containing: midnight, calendar: calendar)

            XCTAssertEqual(intervals.last30DayStarts[0], midnight)
            XCTAssertEqual(intervals.last30Days.upperBound, nextMidnight)
            XCTAssertEqual(intervals.last30DayIndex(containing: midnight), 0)
            XCTAssertEqual(intervals.last30DayIndex(containing: nextMidnight.addingTimeInterval(-0.001)), 0)
            XCTAssertNil(intervals.last30DayIndex(containing: nextMidnight))
            XCTAssertEqual(intervals.last30DayIndex(containing: intervals.last30Days.lowerBound), 29)
            XCTAssertEqual(intervals.last30DayStarts.last, intervals.last30Days.lowerBound)
            XCTAssertNil(
                intervals.last30DayIndex(containing: intervals.last30Days.lowerBound.addingTimeInterval(-0.001))
            )
        }
    }
}
