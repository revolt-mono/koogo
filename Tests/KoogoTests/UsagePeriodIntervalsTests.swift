import Foundation
import XCTest

@testable import Koogo

final class UsagePeriodIntervalsTests: XCTestCase {
    func testCalendarPeriodsUseLocalCalendarAndConfiguredFirstWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 2
        let date = try XCTUnwrap(parseUsageTimestamp("2026-03-11T12:00:00.000Z"))
        let intervals = UsagePeriodIntervals(containing: date, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.day.current.lowerBound),
            DateComponents(year: 2026, month: 3, day: 11)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.week.lowerBound),
            DateComponents(year: 2026, month: 3, day: 9)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.month.current.lowerBound),
            DateComponents(year: 2026, month: 3, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.day.previous.lowerBound),
            DateComponents(year: 2026, month: 3, day: 10)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.month.previous.lowerBound),
            DateComponents(year: 2026, month: 2, day: 1)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: intervals.month.previous.upperBound),
            DateComponents(year: 2026, month: 3, day: 1)
        )
    }
}
