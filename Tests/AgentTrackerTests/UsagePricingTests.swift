import Foundation
import XCTest

@testable import AgentTracker

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

        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: event)), 890_000_000)
    }

    func testCodexLongContextAndFastRatesApplyToTheWholeRequest() throws {
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
        let fast = codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 100_000,
            output: 10_000,
            serviceTier: .fast
        )

        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: atBoundary)), 1_088_000_000)
        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: long)), 2_176_008_000)
        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: fast)), 1_200_000_000)
    }

    func testCodexFlexRatesAreExactAndUnsupportedModelsAreIgnored() throws {
        let long = codexEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 272_001,
            output: 0,
            serviceTier: .flex
        )
        let fractional = codexEvent(
            model: "gpt-5.4-mini",
            uncachedInput: 0,
            cachedInput: 1,
            output: 0,
            serviceTier: .flex
        )
        let unsupported = codexEvent(
            model: "gpt-5.3-codex",
            uncachedInput: 100,
            output: 10,
            serviceTier: .flex
        )

        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: long)), 1_088_004_000)
        XCTAssertEqual(
            try XCTUnwrap(catalog.costNanodollars(for: fractional)),
            Decimal(375) / 10
        )
        XCTAssertNil(catalog.costNanodollars(for: unsupported))
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

        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: event)), 5_355_000_000)
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

        XCTAssertEqual(try XCTUnwrap(catalog.costNanodollars(for: snapshot)), 450_000)
        XCTAssertEqual(
            catalog.costNanodollars(for: snapshot),
            catalog.costNanodollars(for: alias)
        )
        for model in ["claude-opus-4-5", "claude-haiku-4-5"] {
            XCTAssertNotNil(catalog.costNanodollars(for: claudeEvent(
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
            XCTAssertNil(catalog.costNanodollars(for: claudeEvent(
                model: model,
                uncachedInput: 1
            )))
        }
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
                effort: "high",
                uncachedInput: 200_000,
                output: 0
            ),
        ]

        let snapshot = UsageSnapshotBuilder(priceCatalog: catalog).build(
            events: events,
            at: timestamp,
            intervals: intervals,
            calendar: calendar
        )
        let today = snapshot[.codex][.today]

        XCTAssertEqual(today.processedTokens, 240_000)
        XCTAssertEqual(today.costUSD, Decimal(string: "0.808"))
        XCTAssertEqual(today.favoriteModel, "gpt-5.6-luna")
        XCTAssertEqual(today.favoriteReasoningEffort, "high")
        XCTAssertEqual(
            snapshot.codex.dailyMonth.days,
            [
                UsageDaySnapshot(
                    date: calendar.startOfDay(for: timestamp),
                    processedTokens: 240_000,
                    costUSD: try XCTUnwrap(Decimal(string: "0.808"))
                )
            ]
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
            at: timestamp,
            intervals: intervals,
            calendar: calendar
        )
        let total = snapshot.codex.today.costUSD + snapshot.claude.today.costUSD

        XCTAssertEqual(snapshot.codex.today.costUSD, Decimal(string: "0.004"))
        XCTAssertEqual(snapshot.claude.today.costUSD, Decimal(string: "0.005"))
        XCTAssertEqual(total, Decimal(string: "0.009"))
        XCTAssertEqual(UsageFormatting.cost(snapshot.claude.today.costUSD), "$0.01")
        XCTAssertEqual(UsageFormatting.cost(total), "$0.01")
        XCTAssertEqual(
            UsageFormatting.cost(try XCTUnwrap(Decimal(string: "0.025"))),
            "$0.03"
        )
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
            at: timestamp,
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.codex.today.processedTokens, 100)
        XCTAssertEqual(snapshot.codex.week.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.month.processedTokens, 150)
        XCTAssertEqual(snapshot.codex.dailyMonth.interval, intervals.month)
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
            at: now,
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
            at: timestamp,
            intervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(snapshot[.codex][.month], .zero)
    }

    private func codexEvent(
        id: Int = 0,
        model: String,
        effort: String? = nil,
        uncachedInput: Int64,
        cachedInput: Int64 = 0,
        cacheWriteInput: Int64 = 0,
        output: Int64 = 0,
        serviceTier: UsageEvent.Codex.ServiceTier = .standard,
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
            cumulativeTotal: tokens.processed,
            serviceTier: serviceTier
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
