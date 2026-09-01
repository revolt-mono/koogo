import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotBuilderTests: XCTestCase {
    func testSnapshotPreservesSubcentProviderCostsUntilDisplayFormatting() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals(endingAt: usageTestTimestamp)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(model: "gpt-5.6-sol", uncachedInput: 1_000),
                claudeUsageEvent(model: "claude-opus-5", uncachedInput: 1_000),
            ],
            intervals: intervals,
            calendar: calendar
        )
        let total = snapshot.codex.last24Hours.costUSD + snapshot.claude.last24Hours.costUSD

        XCTAssertEqual(snapshot.codex.last24Hours.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.claude.last24Hours.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(total, Decimal(string: "0.01"))
        XCTAssertEqual(UsageFormatting.cost(snapshot.claude.last24Hours.costUSD), "$0.01")
        XCTAssertEqual(UsageFormatting.cost(total), "$0.01")
        XCTAssertEqual(
            UsageFormatting.cost(try XCTUnwrap(Decimal(string: "0.025"))),
            "$0.03"
        )
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

        XCTAssertEqual(UsageFormatting.percentage(1), "100%")
        XCTAssertEqual(UsageFormatting.percentage(0), "0%")
        XCTAssertEqual(
            UsageFormatting.percentage(
                try XCTUnwrap(Decimal(string: "0.125"))
            ),
            "12.5%"
        )
    }

    func testSnapshotComparesAdjacentRollingPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T17:00:00Z"))
                ),
                claudeUsageEvent(
                    model: "claude-opus-5",
                    uncachedInput: 10_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T17:30:00Z"))
                ),
                codexUsageEvent(
                    id: 3,
                    model: "gpt-5.6-sol",
                    uncachedInput: 2_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T17:00:00Z"))
                ),
                claudeUsageEvent(
                    model: "claude-opus-5",
                    uncachedInput: 20_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T19:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(endingAt: usageTestTimestamp),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.last24Hours.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .decrease(fraction: Decimal(1) / 2))
    }

    func testLast30DaysExcludesLowerBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-03-31T12:00:00Z"))

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-03-01T12:00:00Z"))
                ),
                codexUsageEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 10_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-03-01T12:00:01Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(endingAt: now),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.last30Days.current.costUSD, Decimal(string: "0.05"))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .increase(fraction: 9))
    }

    func testSnapshotDerivesRollingPeriodsAndDailySeries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals(endingAt: usageTestTimestamp)
        let boundary24HoursAgo = usageTestTimestamp.addingTimeInterval(-24 * 60 * 60)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(id: 1, model: "gpt-5.6-sol", uncachedInput: 100),
                codexUsageEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 50,
                    at: boundary24HoursAgo
                ),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.last7Days.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.last30Days.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.last30DaysByDay.interval, intervals.last30Days.current)
        XCTAssertEqual(
            snapshot.codex.last30DaysByDay.days.map(\.processedTokens),
            [50, 100]
        )
    }

    func testRollingPeriodsIgnoreCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-09-01T12:00:00Z"))
        let boundary24HoursAgo = try XCTUnwrap(parseUsageTimestamp("2026-08-31T12:00:00Z"))
        let intervals = UsagePeriodIntervals(endingAt: now)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(model: "gpt-5.6-sol", uncachedInput: 100, at: now),
                codexUsageEvent(
                    model: "gpt-5.6-sol",
                    uncachedInput: 50,
                    at: boundary24HoursAgo
                ),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.last7Days.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.last30Days.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.last30DaysByDay.days.map(\.processedTokens), [50, 100])
    }

    func testDailySeriesTruncatesInUserTimeZoneAfterApplyingRollingCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-03-11T12:00:00Z"))
        let lowerBound = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let included = lowerBound.addingTimeInterval(1)

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 100,
                    at: included
                ),
                codexUsageEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 50,
                    at: lowerBound.addingTimeInterval(-1)
                ),
            ],
            intervals: UsagePeriodIntervals(endingAt: now),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.last30Days.processedTokens, 100)
        XCTAssertEqual(
            snapshot.codex.last30DaysByDay.days,
            [
                UsageDaySnapshot(
                    date: calendar.startOfDay(for: included),
                    processedTokens: 100,
                    costUSD: try XCTUnwrap(Decimal(string: "0.0005"))
                )
            ]
        )
    }
}
