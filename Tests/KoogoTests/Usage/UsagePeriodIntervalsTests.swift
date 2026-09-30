import Foundation
import XCTest

@testable import Koogo

final class UsagePeriodIntervalsTests: XCTestCase {
    func testRollingPeriodsUseLocalMidnightsAcrossMonthBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(Date(iso8601: "2026-03-11T12:00:00Z"))
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

        XCTAssertEqual(intervals.today, Date(iso8601: "2026-03-11T07:00:00Z"))
        XCTAssertEqual(intervals.yesterday, Date(iso8601: "2026-03-10T07:00:00Z"))
        XCTAssertEqual(intervals.last7DaysStart, Date(iso8601: "2026-03-05T08:00:00Z"))
        XCTAssertEqual(intervals.last30Days.lowerBound, Date(iso8601: "2026-02-10T08:00:00Z"))
        XCTAssertEqual(intervals.last30Days.upperBound, Date(iso8601: "2026-03-12T07:00:00Z"))
        XCTAssertEqual(intervals.previous30Days.lowerBound, Date(iso8601: "2026-01-11T08:00:00Z"))
        XCTAssertEqual(intervals.previous30Days.upperBound, intervals.last30Days.lowerBound)
        XCTAssertEqual(intervals.historyStart, intervals.previous30Days.lowerBound)
        XCTAssertEqual(intervals.last30Day(containing: date), intervals.today)
    }

    func testRollingPeriodsIgnoreTimeOfDay() throws {
        let midnight = try XCTUnwrap(Date(iso8601: "2026-09-01T00:00:00Z"))
        let lastMillisecond = try XCTUnwrap(Date(iso8601: "2026-09-01T23:59:59.999Z"))
        let morning = UsagePeriodIntervals(containing: midnight, calendar: usageTestCalendar)
        let evening = UsagePeriodIntervals(containing: lastMillisecond, calendar: usageTestCalendar)

        XCTAssertEqual(morning, evening)
        XCTAssertEqual(morning.last7DaysStart, Date(iso8601: "2026-08-26T00:00:00Z"))
        XCTAssertEqual(morning.last30Days.lowerBound, Date(iso8601: "2026-08-03T00:00:00Z"))
        XCTAssertEqual(morning.previous30Days.lowerBound, Date(iso8601: "2026-07-04T00:00:00Z"))
    }

    func testMidnightDaylightSavingTransitionKeepsPreviousDayWhole() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Havana"))
        let date = try XCTUnwrap(Date(iso8601: "2026-03-08T12:00:00Z"))
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

        XCTAssertEqual(intervals.today, Date(iso8601: "2026-03-08T05:00:00Z"))
        XCTAssertEqual(intervals.last30Days.upperBound, Date(iso8601: "2026-03-09T04:00:00Z"))
        XCTAssertEqual(intervals.yesterday, Date(iso8601: "2026-03-07T05:00:00Z"))
    }

    func testDailyBucketsFollowMidnightAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (start, end, hours) in [
            ("2026-03-08T08:00:00Z", "2026-03-09T07:00:00Z", 23),
            ("2026-11-01T07:00:00Z", "2026-11-02T08:00:00Z", 25),
        ] {
            let midnight = try XCTUnwrap(Date(iso8601: start))
            let nextMidnight = try XCTUnwrap(Date(iso8601: end))
            let intervals = UsagePeriodIntervals(containing: midnight, calendar: calendar)

            XCTAssertEqual(intervals.today, midnight)
            XCTAssertEqual(intervals.last30Days.upperBound, nextMidnight)
            XCTAssertEqual(nextMidnight.timeIntervalSince(midnight), Double(hours * 60 * 60))
            XCTAssertEqual(intervals.last30Day(containing: midnight), midnight)
            XCTAssertEqual(intervals.last30Day(containing: nextMidnight.addingTimeInterval(-0.001)), midnight)
            XCTAssertNil(intervals.last30Day(containing: nextMidnight))
            XCTAssertEqual(
                intervals.last30Day(containing: intervals.last30Days.lowerBound),
                intervals.last30Days.lowerBound
            )
            XCTAssertNil(
                intervals.last30Day(containing: intervals.last30Days.lowerBound.addingTimeInterval(-0.001))
            )
        }
    }
}
