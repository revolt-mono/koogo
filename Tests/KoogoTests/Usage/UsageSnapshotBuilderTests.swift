import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotBuilderTests: XCTestCase {
    func testSnapshotPreservesSubcentProviderCosts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, processedTokens: 1_000, costUSD: 0.005),
                usageEvent(.claude, processedTokens: 1_000, costUSD: 0.005),
            ],
            intervals: intervals,
            calendar: calendar
        )
        let total = snapshot.codex.today.costUSD + snapshot.claude.today.costUSD

        XCTAssertEqual(snapshot.codex.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.claude.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(total, Decimal(string: "0.01"))
    }

    func testCostChangeUsesStockStyleZeroBaseline() throws {
        for (current, previous, expected) in [
            (Decimal(5), Decimal(0), UsageCostChange.increase(fraction: 1)),
            (Decimal(0), Decimal(5), .decrease(fraction: 1)),
            (Decimal(0), Decimal(0), .unchanged),
            (Decimal(15), Decimal(10), .increase(fraction: Decimal(1) / 2)),
            (Decimal(5), Decimal(10), .decrease(fraction: Decimal(1) / 2)),
        ] {
            let change = UsageCostChange(currentUSD: current, previousUSD: previous)
            XCTAssertEqual(change, expected)
        }
    }

    func testSnapshotComparesCompletePreviousPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(
                    .codex,
                    id: 1,
                    processedTokens: 1_000,
                    costUSD: 0.005,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T17:00:00Z"))
                ),
                usageEvent(
                    .claude,
                    processedTokens: 10_000,
                    costUSD: 0.05,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T19:00:00Z"))
                ),
                usageEvent(
                    .codex,
                    id: 3,
                    processedTokens: 2_000,
                    costUSD: 0.01,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T17:00:00Z"))
                ),
                usageEvent(
                    .claude,
                    processedTokens: 20_000,
                    costUSD: 0.1,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T19:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.month.costChange, .decrease(fraction: Decimal(1) / 2))
    }

    func testPreviousMonthExcludesCurrentMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-03-31T12:00:00Z"))

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(
                    .codex,
                    id: 1,
                    processedTokens: 1_000,
                    costUSD: 0.005,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-02-28T23:59:59Z"))
                ),
                usageEvent(
                    .codex,
                    id: 2,
                    processedTokens: 10_000,
                    costUSD: 0.05,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-03-01T00:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(containing: now, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.month.current.costUSD, Decimal(string: "0.05"))
        XCTAssertEqual(snapshot.summary.month.costChange, .increase(fraction: 9))
    }

    func testSnapshotDerivesCalendarPeriodsAndDailySeries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar)
        let within24HoursOnPreviousDay = try XCTUnwrap(
            calendar.date(byAdding: .hour, value: -23, to: usageTestTimestamp)
        )

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, id: 1, processedTokens: 100, costUSD: 1),
                usageEvent(
                    .codex,
                    id: 2,
                    processedTokens: 50,
                    costUSD: 1,
                    at: within24HoursOnPreviousDay
                ),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.today.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.week.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.month.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.dailyMonth.range, intervals.month.current)
        XCTAssertEqual(
            snapshot.codex.dailyMonth.days.map(\.processedTokens),
            [50, 100]
        )
    }

    func testSnapshotUsesCalendarWeekAndMonthBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(parseUsageTimestamp("2026-09-01T12:00:00Z"))
        let sameWeekPreviousMonth = try XCTUnwrap(
            parseUsageTimestamp("2026-08-31T12:00:00Z")
        )
        let previousCalendarWeek = try XCTUnwrap(
            parseUsageTimestamp("2026-08-30T12:00:00Z")
        )
        let intervals = UsagePeriodIntervals(containing: now, calendar: calendar)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, processedTokens: 100, costUSD: 1, at: now),
                usageEvent(
                    .codex,
                    processedTokens: 50,
                    costUSD: 1,
                    at: sameWeekPreviousMonth
                ),
                usageEvent(
                    .codex,
                    processedTokens: 25,
                    costUSD: 1,
                    at: previousCalendarWeek
                ),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.today.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.week.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.month.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.dailyMonth.days.map(\.processedTokens), [100])
    }
}
