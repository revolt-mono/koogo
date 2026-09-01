import Foundation
import XCTest

@testable import Koogo

final class UsageSnapshotFavoriteTests: XCTestCase {
    func testSnapshotPreservesExactCostsAndUsesOccurrenceFavorites() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let snapshot = UsageSnapshotBuilder.build(
            events: [
                codexUsageEvent(
                    id: 1,
                    model: "gpt-5.6-luna",
                    effort: "low",
                    uncachedInput: 20_000
                ),
                codexUsageEvent(
                    id: 2,
                    model: "gpt-5.6-luna",
                    effort: "high",
                    uncachedInput: 20_000
                ),
                codexUsageEvent(
                    id: 3,
                    model: "gpt-5.6-sol",
                    effort: "low",
                    uncachedInput: 200_000
                ),
            ],
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
            events: [
                codexUsageEvent(
                    id: 1,
                    model: "gpt-5.6-luna",
                    effort: "high",
                    uncachedInput: 1,
                    at: earlierHistory
                ),
                codexUsageEvent(
                    id: 2,
                    model: "gpt-5.6-luna",
                    effort: "high",
                    uncachedInput: 1,
                    at: earlierHistory
                ),
                codexUsageEvent(
                    id: 3,
                    model: "gpt-5.6-luna",
                    effort: "low",
                    uncachedInput: 1,
                    at: earlierHistory
                ),
                codexUsageEvent(
                    id: 4,
                    model: "gpt-5.6-sol",
                    effort: "low",
                    uncachedInput: 1
                ),
                codexUsageEvent(
                    id: 5,
                    model: "gpt-5.6-sol",
                    effort: "low",
                    uncachedInput: 1
                ),
            ],
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
}
