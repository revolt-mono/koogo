import XCTest

@testable import Koogo

final class UsagePricingTests: XCTestCase {
    func testCodexPricesOrdinaryCachedWritesAndOutputSeparately() throws {
        let quote = try XCTUnwrap(
            CodexUsagePricing.quote(
                model: "gpt-5.6-sol",
                tokens: codexTokenUsage(
                    uncachedInput: 100_000,
                    cachedInput: 100_000,
                    cacheWriteInput: 50_000,
                    output: 10_000
                )
            )
        )

        XCTAssertEqual(quote.costUSD, Decimal(string: "1.1625"))
    }

    func testCodexLongContextRatesApplyToTheWholeRequest() throws {
        let atBoundary = try XCTUnwrap(
            CodexUsagePricing.quote(
                model: "gpt-5.6-sol",
                tokens: codexTokenUsage(uncachedInput: 272_000)
            )
        )
        let long = try XCTUnwrap(
            CodexUsagePricing.quote(
                model: "gpt-5.6-sol",
                tokens: codexTokenUsage(uncachedInput: 272_001)
            )
        )

        XCTAssertEqual(atBoundary.costUSD, Decimal(string: "1.36"))
        XCTAssertEqual(long.costUSD, Decimal(string: "2.72001"))
    }

    func testClaudePricesCacheDurationsFastGeoAndSearches() throws {
        let quote = try XCTUnwrap(
            ClaudeUsagePricing.quote(
                model: "claude-opus-5",
                usage: claudeBillableUsage(
                    uncachedInput: 100_000,
                    cachedInput: 100_000,
                    cacheWrite5MinuteInput: 100_000,
                    cacheWrite1HourInput: 100_000,
                    output: 10_000,
                    speed: .fast,
                    inferenceGeo: "us",
                    webSearchRequests: 2
                )
            )
        )

        XCTAssertEqual(quote.costUSD, Decimal(string: "5.355"))
    }

    func testClaudePricesAggregateCacheCreationAtTheDefaultRate() throws {
        let quote = try XCTUnwrap(
            ClaudeUsagePricing.quote(
                model: "claude-opus-5",
                usage: ClaudeBillableUsage(
                    tokens: ClaudeTokenUsage(
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
        )

        XCTAssertEqual(quote.costUSD, Decimal(string: "0.000625"))
    }

    func testClaudeSnapshotIDsAndAliasesStartAt45() throws {
        let usage = claudeBillableUsage(uncachedInput: 100, output: 10)
        let snapshot = try XCTUnwrap(
            ClaudeUsagePricing.quote(
                model: "claude-sonnet-4-5-20250929",
                usage: usage
            )
        )
        let alias = try XCTUnwrap(
            ClaudeUsagePricing.quote(model: "claude-sonnet-4-5", usage: usage)
        )

        XCTAssertEqual(snapshot.costUSD, Decimal(string: "0.00045"))
        XCTAssertEqual(snapshot.costUSD, alias.costUSD)
        for model in ["claude-opus-4-5", "claude-haiku-4-5"] {
            XCTAssertNotNil(
                ClaudeUsagePricing.quote(
                    model: model,
                    usage: claudeBillableUsage(uncachedInput: 1)
                )
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
                ClaudeUsagePricing.quote(
                    model: model,
                    usage: claudeBillableUsage(uncachedInput: 1)
                )
            )
        }
    }

    func testQuotesNormalizeAliasesAndProvideModelDisplayNames() throws {
        let codex = try XCTUnwrap(
            CodexUsagePricing.quote(
                model: "gpt-5.6-sol",
                tokens: codexTokenUsage(uncachedInput: 1)
            )
        )
        let codexAlias = try XCTUnwrap(
            CodexUsagePricing.quote(
                model: "gpt-5.6",
                tokens: codexTokenUsage(uncachedInput: 1)
            )
        )
        let claude = try XCTUnwrap(
            ClaudeUsagePricing.quote(
                model: "claude-fable-5",
                usage: claudeBillableUsage(uncachedInput: 1)
            )
        )

        XCTAssertEqual(codex.model, codexAlias.model)
        XCTAssertEqual(codex.model, .codex(id: "gpt-5.6-sol", name: "GPT 5.6 Sol"))
        XCTAssertEqual(claude.model, .claude(id: "claude-fable-5", name: "Claude Fable 5"))
    }
}
