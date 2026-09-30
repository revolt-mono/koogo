import Foundation
import XCTest

@testable import Koogo

final class UsageFavoritesTests: XCTestCase {
    func testFavoritesCountTurnsInsteadOfTokensOrCost() {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(1, model: luna, effort: "low", tokens: 20_000, costUSD: 0.004),
                favoriteEvent(2, model: luna, effort: "high", tokens: 20_000, costUSD: 0.004),
                favoriteEvent(3, model: sol, effort: "low", tokens: 200_000, costUSD: 1),
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

    func testFavoritesUseLast30DaysMidnightBoundaries() throws {
        let beforeWindow = try XCTUnwrap(Date(iso8601: "2026-07-26T23:59:59.999Z"))
        let firstMidnight = try XCTUnwrap(Date(iso8601: "2026-07-27T00:00:00Z"))
        let lastMillisecond = try XCTUnwrap(Date(iso8601: "2026-08-25T23:59:59.999Z"))
        let nextMidnight = try XCTUnwrap(Date(iso8601: "2026-08-26T00:00:00Z"))
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(1, model: luna, effort: "high", at: beforeWindow),
                favoriteEvent(2, model: luna, effort: "high", at: beforeWindow),
                favoriteEvent(3, model: luna, effort: "high", at: beforeWindow),
                favoriteEvent(4, model: sol, effort: "high", at: firstMidnight),
                favoriteEvent(5, model: sol, effort: "high", at: lastMillisecond),
                favoriteEvent(6, model: luna, effort: "high", at: nextMidnight),
                favoriteEvent(7, model: luna, effort: "high", at: nextMidnight),
                favoriteEvent(8, model: luna, effort: "high", at: nextMidnight),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(
            snapshot.providers[.codex]?.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "GPT 5.6 Sol", reasoningEffort: "high")
        )
    }

    func testFavoriteEffortsUseOnlyRecentTurnsOfTheFavoriteModel() throws {
        let earlierHistory = try XCTUnwrap(Date(iso8601: "2026-07-26T12:00:00Z"))
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(1, model: sol, effort: "low", at: earlierHistory),
                favoriteEvent(2, model: sol, effort: "low", at: earlierHistory),
                favoriteEvent(3, model: sol, effort: "low", at: earlierHistory),
                favoriteEvent(4, model: sol, effort: "high"),
                favoriteEvent(5, model: sol, effort: "high"),
                favoriteEvent(6, model: luna, effort: "low"),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertEqual(
            snapshot.providers[.codex]?.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "GPT 5.6 Sol", reasoningEffort: "high")
        )
    }

    func testFavoriteIsAbsentWithoutTurnsInLast30Days() throws {
        let snapshot = UsageSnapshotBuilder.build(
            events: [
                favoriteEvent(
                    1,
                    model: luna,
                    effort: "high",
                    at: try XCTUnwrap(Date(iso8601: "2026-07-26T23:59:59.999Z"))
                ),
                favoriteEvent(
                    2,
                    model: sol,
                    effort: "low",
                    at: try XCTUnwrap(Date(iso8601: "2026-08-26T00:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )

        XCTAssertNil(snapshot.providers[.codex]?.favorite)
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

private let luna = UsageModelReference(id: "gpt-5.6-luna", name: "GPT 5.6 Luna")
private let sol = UsageModelReference(id: "gpt-5.6-sol", name: "GPT 5.6 Sol")
