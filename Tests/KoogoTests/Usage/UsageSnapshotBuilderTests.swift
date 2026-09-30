import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotBuilderTests: XCTestCase {
    func testSnapshotPreservesSubcentProviderCosts() {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, id: 1, processedTokens: 1_000, costUSD: 0.005),
                usageEvent(.codex, id: 2, processedTokens: 1_000, costUSD: 0.004),
                usageEvent(.claude, processedTokens: 1_000, costUSD: 0.005),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )
        XCTAssertEqual(snapshot.providers[.codex]?.today.costUSD, Decimal(string: "0.009"))
        XCTAssertEqual(snapshot.providers[.codex]?.last30Days.costUSD, Decimal(string: "0.009"))
        XCTAssertEqual(snapshot.providers[.claude]?.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.summary.today.current.costUSD, Decimal(string: "0.014"))
    }

    func testTokenTotalsSaturateInsteadOfOverflowing() {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.piAgent, id: 1, processedTokens: .max, costUSD: 0),
                usageEvent(.piAgent, id: 2, processedTokens: 1, costUSD: 0),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )
        XCTAssertEqual(snapshot.summary.last30Days.current.processedTokens, .max)
    }

    func testCostChangeUsesStockStyleZeroBaseline() {
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
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(
                    .codex,
                    id: 1,
                    processedTokens: 1_000,
                    costUSD: 0.005,
                    at: try XCTUnwrap(Date(iso8601: "2026-08-24T17:00:00Z"))
                ),
                usageEvent(
                    .claude,
                    processedTokens: 10_000,
                    costUSD: 0.05,
                    at: try XCTUnwrap(Date(iso8601: "2026-08-24T19:00:00Z"))
                ),
                usageEvent(
                    .codex,
                    id: 3,
                    processedTokens: 2_000,
                    costUSD: 0.01,
                    at: try XCTUnwrap(Date(iso8601: "2026-07-25T17:00:00Z"))
                ),
                usageEvent(
                    .claude,
                    processedTokens: 20_000,
                    costUSD: 0.1,
                    at: try XCTUnwrap(Date(iso8601: "2026-07-25T19:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .decrease(fraction: Decimal(1) / 2))
    }

    func testSummaryComparisonIgnoresProvidersOutsideTheSet() throws {
        let yesterday = try XCTUnwrap(usageTestCalendar.date(byAdding: .day, value: -1, to: usageTestTimestamp))

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, processedTokens: 100, costUSD: 1),
                usageEvent(.claude, processedTokens: 100, costUSD: 1, at: yesterday),
            ],
            providers: [.codex],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(Set(snapshot.providers.keys), [.codex])
        XCTAssertEqual(snapshot.summary.today.costChange, .increase(fraction: 1))
    }

    func testPrevious30DaysExcludesCurrentWindowBoundary() throws {
        let now = try XCTUnwrap(Date(iso8601: "2026-03-31T12:00:00Z"))

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(
                    .codex,
                    id: 1,
                    processedTokens: 1_000,
                    costUSD: 0.005,
                    at: try XCTUnwrap(Date(iso8601: "2026-03-01T23:59:59Z"))
                ),
                usageEvent(
                    .codex,
                    id: 2,
                    processedTokens: 10_000,
                    costUSD: 0.05,
                    at: try XCTUnwrap(Date(iso8601: "2026-03-02T00:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(containing: now, calendar: usageTestCalendar)
        )

        XCTAssertEqual(snapshot.summary.last30Days.current.costUSD, Decimal(string: "0.05"))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .increase(fraction: 9))
    }

    func testSnapshotUsesRollingWindowsAndMidnightBoundaries() throws {
        let now = try XCTUnwrap(Date(iso8601: "2026-09-01T12:00:00Z"))
        let intervals = UsagePeriodIntervals(containing: now, calendar: usageTestCalendar)
        let rows: [(String, UInt64)] = [
            ("2026-07-03T23:59:59.999Z", 1_024),
            ("2026-07-04T00:00:00Z", 2),
            ("2026-08-02T23:59:59.999Z", 4),
            ("2026-08-03T00:00:00Z", 8),
            ("2026-08-25T23:59:59.999Z", 16),
            ("2026-08-26T00:00:00Z", 32),
            ("2026-08-31T23:59:59.999Z", 64),
            ("2026-09-01T00:00:00Z", 128),
            ("2026-09-01T23:59:59.999Z", 256),
            ("2026-09-02T00:00:00Z", 512),
        ]
        let events = try rows.enumerated().map { index, row in
            usageEvent(
                .codex,
                id: index,
                processedTokens: row.1,
                costUSD: Decimal(row.1),
                at: try XCTUnwrap(Date(iso8601: row.0))
            )
        }

        let snapshot = UsageSnapshotBuilder.build(events: events, intervals: intervals)
        let codex = try XCTUnwrap(snapshot.providers[.codex])

        XCTAssertEqual(codex.today.processedTokens, 384)
        XCTAssertEqual(codex.last7Days.processedTokens, 480)
        XCTAssertEqual(codex.last30Days.processedTokens, 504)
        XCTAssertEqual(codex.dailyLast30Days.days.map(\.usage.processedTokens), [8, 16, 32, 64, 384])
        XCTAssertEqual(codex.dailyLast30Days.days.map(\.usage).reduce(UsagePeriodSnapshot(), +), codex.last30Days)
        XCTAssertEqual(codex.dailyLast30Days.range.lowerBound, Date(iso8601: "2026-08-03T00:00:00Z"))
        XCTAssertEqual(codex.dailyLast30Days.range.upperBound, Date(iso8601: "2026-09-02T00:00:00Z"))
        XCTAssertEqual(snapshot.summary.last30Days.current, codex.last30Days)
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .increase(fraction: 83))
        XCTAssertEqual(snapshot.summary.today.costChange, .increase(fraction: 5))
    }
}
