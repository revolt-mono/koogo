import XCTest

@testable import Koogo

final class UsagePricingTests: XCTestCase {
    func testCodexPricesOrdinaryCachedWritesAndOutputSeparately() throws {
        let event = codexUsageEvent(
            model: "gpt-5.6-sol",
            uncachedInput: 100_000,
            cachedInput: 100_000,
            cacheWriteInput: 50_000,
            output: 10_000
        )

        XCTAssertEqual(
            try XCTUnwrap(event.quote).costNanodollars,
            1_162_500_000
        )
    }

    func testCodexLongContextRatesApplyToTheWholeRequest() throws {
        let atBoundary = codexUsageEvent(model: "gpt-5.6-sol", uncachedInput: 272_000)
        let long = codexUsageEvent(model: "gpt-5.6-sol", uncachedInput: 272_001)

        XCTAssertEqual(
            try XCTUnwrap(atBoundary.quote).costNanodollars,
            1_360_000_000
        )
        XCTAssertEqual(
            try XCTUnwrap(long.quote).costNanodollars,
            2_720_010_000
        )
    }

    func testClaudePricesCacheDurationsFastGeoAndSearches() throws {
        let event = claudeUsageEvent(
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

        XCTAssertEqual(try XCTUnwrap(event.quote).costNanodollars, 5_355_000_000)
    }

    func testClaudePricesAggregateCacheCreationAtTheDefaultRate() throws {
        let event = UsageEvent.claude(
            UsageEvent.Claude(
                messageID: "message",
                requestID: "request",
                details: UsageEvent.Details(
                    timestamp: usageTestTimestamp,
                    model: "claude-opus-5",
                    reasoningEffort: nil
                ),
                tokens: UsageEvent.Claude.Tokens(
                    input: 0,
                    cacheRead: 0,
                    cacheCreation: .aggregate(100),
                    output: 0
                ),
                speed: .standard,
                inferenceGeo: nil,
                webSearchRequests: 0
            )
        )

        XCTAssertEqual(
            try XCTUnwrap(event.quote).costNanodollars,
            625_000
        )
    }

    func testClaudeSnapshotIDsAndAliasesStartAt45() throws {
        let snapshot = claudeUsageEvent(
            model: "claude-sonnet-4-5-20250929",
            uncachedInput: 100,
            output: 10
        )
        let alias = claudeUsageEvent(
            model: "claude-sonnet-4-5",
            uncachedInput: 100,
            output: 10
        )

        XCTAssertEqual(try XCTUnwrap(snapshot.quote).costNanodollars, 450_000)
        XCTAssertEqual(snapshot.quote?.costNanodollars, alias.quote?.costNanodollars)
        for model in ["claude-opus-4-5", "claude-haiku-4-5"] {
            XCTAssertNotNil(
                claudeUsageEvent(model: model, uncachedInput: 1).quote
            )
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
            XCTAssertNil(
                claudeUsageEvent(model: model, uncachedInput: 1).quote
            )
        }
    }

    func testQuotesNormalizeAliasesAndProvideModelDisplayNames() throws {
        let codex = try XCTUnwrap(
            codexUsageEvent(model: "gpt-5.6-sol", uncachedInput: 1).quote
        )
        let codexAlias = try XCTUnwrap(
            codexUsageEvent(model: "gpt-5.6", uncachedInput: 1).quote
        )
        let claude = try XCTUnwrap(
            claudeUsageEvent(model: "claude-fable-5", uncachedInput: 1).quote
        )

        XCTAssertEqual(codex.model, codexAlias.model)
        XCTAssertEqual(codex.model.displayName, "GPT 5.6 Sol")
        XCTAssertEqual(claude.model.displayName, "Claude Fable 5")
    }
}
