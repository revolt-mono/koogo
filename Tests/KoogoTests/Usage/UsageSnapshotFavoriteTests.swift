import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotFavoriteTests: XCTestCase {
    func testSnapshotPreservesExactCostsAndUsesOccurrenceFavorites() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let snapshot = UsageSnapshotBuilder.build(
            events: exactCostEvents(),
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.today.processedTokens, 240_000)
        XCTAssertEqual(snapshot.codex.today.costUSD, Decimal(string: "1.008"))
        XCTAssertEqual(
            snapshot.codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Luna",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(
            snapshot.codex.dailyMonth.days,
            [
                UsageDaySnapshot(
                    date: calendar.startOfDay(for: usageTestTimestamp),
                    processedTokens: 240_000,
                    costUSD: try XCTUnwrap(Decimal(string: "1.008"))
                )
            ]
        )
    }

    func testSnapshotFavoritesUseFullParsedRangeAndFavoriteModelEfforts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let earlierHistory = try XCTUnwrap(parseUsageTimestamp("2026-07-10T12:00:00Z"))
        let snapshot = UsageSnapshotBuilder.build(
            events: historyEvents(at: earlierHistory),
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(
            snapshot.codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Luna",
                reasoningEffort: "high"
            )
        )
    }

    private func exactCostEvents() -> [UsageEvent] {
        let luna = UsageModelReference.codex(id: "gpt-5.6-luna", name: "GPT 5.6 Luna")
        let sol = UsageModelReference.codex(id: "gpt-5.6-sol", name: "GPT 5.6 Sol")
        return [
            favoriteEvent(1, model: luna, effort: "low", tokens: 20_000, costUSD: 0.004),
            favoriteEvent(2, model: luna, effort: "high", tokens: 20_000, costUSD: 0.004),
            favoriteEvent(3, model: sol, effort: "low", tokens: 200_000, costUSD: 1),
        ]
    }

    private func historyEvents(at earlierHistory: Date) -> [UsageEvent] {
        let luna = UsageModelReference.codex(id: "gpt-5.6-luna", name: "GPT 5.6 Luna")
        let sol = UsageModelReference.codex(id: "gpt-5.6-sol", name: "GPT 5.6 Sol")
        return [
            favoriteEvent(1, model: luna, effort: "high", at: earlierHistory),
            favoriteEvent(2, model: luna, effort: "high", at: earlierHistory),
            favoriteEvent(3, model: luna, effort: "low", at: earlierHistory),
            favoriteEvent(4, model: sol, effort: "low"),
            favoriteEvent(5, model: sol, effort: "low"),
        ]
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
