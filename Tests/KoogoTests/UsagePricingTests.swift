import Foundation
import XCTest

@testable import Koogo

final class UsagePricingTests: XCTestCase {
    private let catalog = UsagePriceCatalog()
    private let timestamp = Date(timeIntervalSince1970: 1_787_680_800)

    func testCodexPricesOrdinaryCachedWritesAndOutputSeparately() throws {
        let event = codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 100_000,
            cachedInput: 100_000,
            cacheWriteInput: 50_000,
            output: 10_000
        )

        XCTAssertEqual(
            try XCTUnwrap(catalog.quote(for: event)).costNanodollars,
            1_162_500_000
        )
    }

    func testCodexLongContextRatesApplyToTheWholeRequest() throws {
        let atBoundary = codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 272_000,
            output: 0
        )
        let long = codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 272_001,
            output: 0
        )

        XCTAssertEqual(
            try XCTUnwrap(catalog.quote(for: atBoundary)).costNanodollars,
            1_360_000_000
        )
        XCTAssertEqual(
            try XCTUnwrap(catalog.quote(for: long)).costNanodollars,
            2_720_010_000
        )
    }

    func testClaudePricesCacheDurationsFastGeoAndSearches() throws {
        let event = claudeEvent(
            model: "claude-opus-5",
            uncachedInput: 100_000,
            cachedInput: 100_000,
            cacheWrite5MinuteInput: 100_000,
            cacheWrite1HourInput: 100_000,
            output: 10_000,
            speed: .fast,
            inferenceGeo: "us",
            webSearchRequests: 2
        )

        XCTAssertEqual(try XCTUnwrap(catalog.quote(for: event)).costNanodollars, 5_355_000_000)
    }

    func testClaudeSnapshotIDsAndAliasesStartAt45() throws {
        let snapshot = claudeEvent(
            model: "claude-sonnet-4-5-20250929",
            uncachedInput: 100,
            output: 10
        )
        let alias = claudeEvent(
            model: "claude-sonnet-4-5",
            uncachedInput: 100,
            output: 10
        )

        XCTAssertEqual(try XCTUnwrap(catalog.quote(for: snapshot)).costNanodollars, 450_000)
        XCTAssertEqual(
            catalog.quote(for: snapshot)?.costNanodollars,
            catalog.quote(for: alias)?.costNanodollars
        )
        for model in ["claude-opus-4-5", "claude-haiku-4-5"] {
            XCTAssertNotNil(catalog.quote(for: claudeEvent(
                model: model,
                uncachedInput: 1
            )))
        }
        for model in [
            "claude-opus-4-1-20250805",
            "claude-opus-4-1",
            "claude-opus-4-20250514",
            "claude-opus-4-0",
            "claude-sonnet-4-20250514",
            "claude-sonnet-4-0",
            "claude-3-5-haiku-20241022",
            "claude-3-5-haiku-latest",
        ] {
            XCTAssertNil(catalog.quote(for: claudeEvent(
                model: model,
                uncachedInput: 1
            )))
        }
    }

    func testQuotesNormalizeAliasesAndProvideModelDisplayNames() throws {
        let codex = try XCTUnwrap(catalog.quote(for: codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 1
        )))
        let codexAlias = try XCTUnwrap(catalog.quote(for: codexEvent(
            model: "gpt-5.6",
            uncachedInput: 1
        )))
        let claude = try XCTUnwrap(catalog.quote(for: claudeEvent(
            model: "claude-fable-5",
            uncachedInput: 1
        )))

        XCTAssertEqual(codex.model, codexAlias.model)
        XCTAssertEqual(codex.model.displayName, "GPT 5.6 Sol")
        XCTAssertEqual(claude.model.displayName, "Claude Fable 5")
    }

    func testSnapshotPreservesExactCostsAndUsesOccurrenceFavorites() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals.containing(timestamp, calendar: calendar)
        let events = [
            codexEvent(
                id: 1,
                model: "gpt-5.6-luna",
                effort: "low",
                uncachedInput: 20_000,
                output: 0
            ),
            codexEvent(
                id: 2,
                model: "gpt-5.6-luna",
                effort: "high",
                uncachedInput: 20_000,
                output: 0
            ),
            codexEvent(
                id: 3,
                model: "gpt-5.6-sol",
                effort: "low",
                uncachedInput: 200_000,
                output: 0
            ),
        ]

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: events,
            intervals: intervals,
            calendar: calendar
        )
        let today = snapshot.codex.today

        XCTAssertEqual(today.processedTokens, 240_000)
        XCTAssertEqual(today.costUSD, Decimal(string: "1.008"))
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
                    date: calendar.startOfDay(for: timestamp),
                    processedTokens: 240_000,
                    costUSD: try XCTUnwrap(Decimal(string: "1.008"))
                )
            ]
        )
    }

    func testSnapshotFavoritesUseFullParsedRangeAndFavoriteModelEfforts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-08-25T18:00:00Z"))
        let previousMonth = try XCTUnwrap(parseUsageTimestamp("2026-07-10T12:00:00Z"))
        let events = [
            codexEvent(
                id: 1,
                model: "gpt-5.6-luna",
                effort: "high",
                uncachedInput: 1,
                at: previousMonth
            ),
            codexEvent(
                id: 2,
                model: "gpt-5.6-luna",
                effort: "high",
                uncachedInput: 1,
                at: previousMonth
            ),
            codexEvent(
                id: 3,
                model: "gpt-5.6-luna",
                effort: "low",
                uncachedInput: 1,
                at: previousMonth
            ),
            codexEvent(
                id: 4,
                model: "gpt-5.6-sol",
                effort: "low",
                uncachedInput: 1,
                at: now
            ),
            codexEvent(
                id: 5,
                model: "gpt-5.6-sol",
                effort: "low",
                uncachedInput: 1,
                at: now
            ),
        ]

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: events,
            intervals: UsagePeriodIntervals.containing(now, calendar: calendar),
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

    func testSnapshotPreservesSubcentProviderCostsUntilDisplayFormatting() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals.containing(timestamp, calendar: calendar)

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(model: "gpt-5.6-sol", uncachedInput: 1_000),
                claudeEvent(model: "claude-opus-5", uncachedInput: 1_000),
            ],
            intervals: intervals,
            calendar: calendar
        )
        let total = snapshot.codex.today.costUSD + snapshot.claude.today.costUSD

        XCTAssertEqual(snapshot.codex.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.claude.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(total, Decimal(string: "0.01"))
        XCTAssertEqual(UsageFormatting.cost(snapshot.claude.today.costUSD), "$0.01")
        XCTAssertEqual(UsageFormatting.cost(total), "$0.01")
        XCTAssertEqual(
            UsageFormatting.cost(try XCTUnwrap(Decimal(string: "0.025"))),
            "$0.03"
        )
    }

    func testCostComparisonUsesStockStyleZeroBaseline() throws {
        for (current, previous, direction, fraction) in [
            (Decimal(5), Decimal(0), UsageCostChange.Direction.increase, Decimal(1)),
            (Decimal(0), Decimal(5), .decrease, Decimal(1)),
            (Decimal(0), Decimal(0), .unchanged, Decimal(0)),
            (Decimal(15), Decimal(10), .increase, Decimal(1) / 2),
            (Decimal(5), Decimal(10), .decrease, Decimal(1) / 2),
        ] {
            let change = UsageCostChange(currentUSD: current, previousUSD: previous)
            XCTAssertEqual(change.direction, direction)
            XCTAssertEqual(change.fraction, fraction)
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

    func testSnapshotComparesPreviousPeriodsAtTheSameProgress() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-08-25T18:00:00Z"))
        let intervals = UsagePeriodIntervals.containing(now, calendar: calendar)

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T17:00:00Z"))
                ),
                codexEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 10_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T19:00:00Z"))
                ),
                codexEvent(
                    id: 3,
                    model: "gpt-5.6-sol",
                    uncachedInput: 2_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T17:00:00Z"))
                ),
                codexEvent(
                    id: 4,
                    model: "gpt-5.6-sol",
                    uncachedInput: 20_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-07-25T19:00:00Z"))
                ),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.today.cost.previousUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.summary.month.cost.previousUSD, Decimal(string: "0.01"))
    }

    func testComparisonIncludesBothAlignedCutoffInstants() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-08-25T18:00:00Z"))

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: now
                ),
                codexEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-08-24T18:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals.containing(now, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.today.cost.currentUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.summary.today.cost.previousUSD, Decimal(string: "0.005"))
        XCTAssertEqual(snapshot.summary.today.cost.change.direction, .unchanged)
    }

    func testClippedPreviousMonthExcludesCurrentMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(parseUsageTimestamp("2026-03-31T12:00:00Z"))

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(
                    id: 1,
                    model: "gpt-5.6-sol",
                    uncachedInput: 1_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-02-28T23:59:59Z"))
                ),
                codexEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 10_000,
                    at: try XCTUnwrap(parseUsageTimestamp("2026-03-01T00:00:00Z"))
                ),
            ],
            intervals: UsagePeriodIntervals.containing(now, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshot.summary.month.cost.currentUSD, Decimal(string: "0.05"))
        XCTAssertEqual(snapshot.summary.month.cost.previousUSD, Decimal(string: "0.005"))
    }

    func testSnapshotDerivesPeriodsAndDailySeriesFromDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals.containing(timestamp, calendar: calendar)
        let previousDay = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: timestamp)
        )

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(id: 1, model: "gpt-5.6-sol", uncachedInput: 100),
                codexEvent(
                    id: 2,
                    model: "gpt-5.6-sol",
                    uncachedInput: 50,
                    at: previousDay
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

    func testSnapshotSeparatesWeekAndMonthAcrossMonthBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        let now = try XCTUnwrap(parseUsageTimestamp("2026-09-01T12:00:00Z"))
        let previousMonth = try XCTUnwrap(parseUsageTimestamp("2026-08-31T12:00:00Z"))
        let intervals = UsagePeriodIntervals.containing(now, calendar: calendar)

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [
                codexEvent(model: "gpt-5.6-sol", uncachedInput: 100, at: now),
                codexEvent(model: "gpt-5.6-sol", uncachedInput: 50, at: previousMonth),
            ],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.today.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.week.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.month.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.dailyMonth.days.map(\.processedTokens), [100])
    }

    func testUnknownModelsDoNotEnterAnyStatistic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let intervals = UsagePeriodIntervals.containing(timestamp, calendar: calendar)
        let unknown = codexEvent(
            model: "future-model",
            uncachedInput: 1_000_000,
            output: 1_000_000
        )

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: [unknown],
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.month, .zero)
        XCTAssertNil(snapshot.codex.favorite)
    }

    private func codexEvent(
        id: Int = 0,
        model: String,
        effort: String? = nil,
        uncachedInput: Int64,
        cachedInput: Int64 = 0,
        cacheWriteInput: Int64 = 0,
        output: Int64 = 0,
        at eventDate: Date? = nil
    ) -> UsageEvent {
        let tokens = UsageTokens(
            uncachedInput: uncachedInput,
            cachedInput: cachedInput,
            cacheWrite5MinuteInput: cacheWriteInput,
            cacheWrite1HourInput: 0,
            output: output,
            processed: uncachedInput + cachedInput + cacheWriteInput + output
        )
        return .codex(UsageEvent.Codex(
            threadID: "thread-\(id)",
            turnID: nil,
            ordinal: nil,
            details: UsageEvent.Details(
                timestamp: eventDate ?? timestamp,
                model: model,
                reasoningEffort: effort,
                tokens: tokens
            ),
            reasoningOutput: 0,
            cumulativeTotal: tokens.processed
        ))
    }

    private func claudeEvent(
        model: String,
        uncachedInput: Int64 = 0,
        cachedInput: Int64 = 0,
        cacheWrite5MinuteInput: Int64 = 0,
        cacheWrite1HourInput: Int64 = 0,
        output: Int64 = 0,
        speed: UsageEvent.Claude.Speed = .standard,
        inferenceGeo: String? = nil,
        webSearchRequests: Int64 = 0
    ) -> UsageEvent {
        let tokens = UsageTokens(
            uncachedInput: uncachedInput,
            cachedInput: cachedInput,
            cacheWrite5MinuteInput: cacheWrite5MinuteInput,
            cacheWrite1HourInput: cacheWrite1HourInput,
            output: output,
            processed: uncachedInput
                + cachedInput
                + cacheWrite5MinuteInput
                + cacheWrite1HourInput
                + output
        )
        return .claude(UsageEvent.Claude(
            messageID: "message",
            requestID: "request",
            details: UsageEvent.Details(
                timestamp: timestamp,
                model: model,
                reasoningEffort: nil,
                tokens: tokens
            ),
            speed: speed,
            inferenceGeo: inferenceGeo,
            webSearchRequests: webSearchRequests,
            hasExplicitSpeed: true,
            hasExplicitCacheDuration: true
        ))
    }
}
