import Foundation
import XCTest

@testable import Koogo

final class UsagePeriodIntervalsTests: XCTestCase {
    func testRollingPeriodsUseFixedDurations() throws {
        let date = try XCTUnwrap(parseUsageTimestamp("2026-03-11T12:00:00.000Z"))
        let intervals = UsagePeriodIntervals(endingAt: date)

        XCTAssertEqual(
            intervals.last24Hours.current.lowerBound,
            date.addingTimeInterval(-24 * 60 * 60)
        )
        XCTAssertEqual(
            intervals.last24Hours.previous.lowerBound,
            date.addingTimeInterval(-48 * 60 * 60)
        )
        XCTAssertEqual(
            intervals.last7Days.lowerBound,
            date.addingTimeInterval(-7 * 24 * 60 * 60)
        )
        XCTAssertEqual(
            intervals.last30Days.current.lowerBound,
            date.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        XCTAssertEqual(
            intervals.last30Days.previous.lowerBound,
            date.addingTimeInterval(-60 * 24 * 60 * 60)
        )
    }

    func testRollingPeriodIncludesEndAndAssignsSharedBoundaryToPreviousPeriod() throws {
        let date = try XCTUnwrap(parseUsageTimestamp("2026-03-11T12:00:00.000Z"))
        let periods = UsagePeriodIntervals(endingAt: date).last24Hours

        XCTAssertTrue(periods.current.contains(date))
        XCTAssertFalse(periods.current.contains(periods.current.lowerBound))
        XCTAssertTrue(periods.previous.contains(periods.current.lowerBound))
    }
}
