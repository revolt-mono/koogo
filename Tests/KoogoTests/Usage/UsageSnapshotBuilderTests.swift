import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotBuilderTests: XCTestCase {
    func testSnapshotPreservesSubcentProviderCosts() {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                usageEvent(.codex, processedTokens: 1_000, costUSD: 0.005),
                usageEvent(.claude, processedTokens: 1_000, costUSD: 0.005),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )
        XCTAssertEqual(snapshot.providers[.codex]?.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.providers[.claude]?.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.summary.today.current.costUSD, Decimal(string: "0.01"))
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
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.month.costChange, .decrease(fraction: Decimal(1) / 2))
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

    func testPreviousMonthExcludesCurrentMonthBoundary() throws {
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
            intervals: UsagePeriodIntervals(containing: now, calendar: usageTestCalendar)
        )

        XCTAssertEqual(snapshot.summary.month.current.costUSD, Decimal(string: "0.05"))
        XCTAssertEqual(snapshot.summary.month.costChange, .increase(fraction: 9))
    }

    func testSnapshotDerivesCalendarPeriodsAndDailySeries() throws {
        let intervals = UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        let within24HoursOnPreviousDay = try XCTUnwrap(
            usageTestCalendar.date(byAdding: .hour, value: -23, to: usageTestTimestamp)
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
            intervals: intervals
        )

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 100)
        XCTAssertEqual(snapshot.providers[.codex]?.week.processedTokens, 150)
        XCTAssertEqual(snapshot.providers[.codex]?.month.processedTokens, 150)
        XCTAssertEqual(snapshot.providers[.codex]?.dailyMonth.range, intervals.month.current)
        XCTAssertEqual(
            snapshot.providers[.codex]?.dailyMonth.days.map(\.usage.processedTokens),
            [50, 100]
        )
    }

    func testSnapshotUsesCalendarWeekAndMonthBoundaries() throws {
        let now = try XCTUnwrap(parseUsageTimestamp("2026-09-01T12:00:00Z"))
        let sameWeekPreviousMonth = try XCTUnwrap(
            parseUsageTimestamp("2026-08-31T12:00:00Z")
        )
        let previousCalendarWeek = try XCTUnwrap(
            parseUsageTimestamp("2026-08-30T12:00:00Z")
        )
        let intervals = UsagePeriodIntervals(containing: now, calendar: usageTestCalendar)

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
            intervals: intervals
        )

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 100)
        XCTAssertEqual(snapshot.providers[.codex]?.week.processedTokens, 150)
        XCTAssertEqual(snapshot.providers[.codex]?.month.processedTokens, 100)
        XCTAssertEqual(snapshot.providers[.codex]?.dailyMonth.days.map(\.usage.processedTokens), [100])
    }

    func testSnapshotPreservesExactCostsAndUsesOccurrenceFavorites() throws {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(1, model: luna, effort: "low", tokens: 20_000, costUSD: 0.004),
                favoriteEvent(2, model: luna, effort: "high", tokens: 20_000, costUSD: 0.004),
                favoriteEvent(3, model: sol, effort: "low", tokens: 200_000, costUSD: 1),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        let codex = try XCTUnwrap(snapshot.providers[.codex])
        XCTAssertEqual(codex.today.processedTokens, 240_000)
        XCTAssertEqual(codex.today.costUSD, Decimal(string: "1.008"))
        XCTAssertEqual(
            codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Luna",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(
            codex.dailyMonth.days,
            [
                UsageDaySnapshot(
                    date: usageTestCalendar.startOfDay(for: usageTestTimestamp),
                    usage: codex.today
                )
            ]
        )
    }

    func testSnapshotFavoritesUseFullParsedRangeAndFavoriteModelEfforts() throws {
        let earlierHistory = try XCTUnwrap(parseUsageTimestamp("2026-07-10T12:00:00Z"))
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(1, model: luna, effort: "high", at: earlierHistory),
                favoriteEvent(2, model: luna, effort: "high", at: earlierHistory),
                favoriteEvent(3, model: luna, effort: "low", at: earlierHistory),
                favoriteEvent(4, model: sol, effort: "low"),
                favoriteEvent(5, model: sol, effort: "low"),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(
            snapshot.providers[.codex]?.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Luna",
                reasoningEffort: "high"
            )
        )
    }

    private func favoriteEvent(
        _ id: Int,
        model: UsageModelReference,
        effort: String,
        tokens: UInt64 = 1,
        costUSD: Decimal = 0,
        at date: Date = usageTestTimestamp
    ) -> UsageEvent {
        usageEvent(
            .codex,
            id: id,
            model: model,
            effort: effort,
            processedTokens: tokens,
            costUSD: costUSD,
            at: date
        )
    }
}

private let luna = UsageModelReference.named(id: "gpt-5.6-luna", name: "GPT 5.6 Luna")
private let sol = UsageModelReference.named(id: "gpt-5.6-sol", name: "GPT 5.6 Sol")
