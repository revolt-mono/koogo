import Foundation
import XCTest

@testable import Koogo

final class CodexUsageTests: UsageWorkspaceTestCase {
    func testCodexUsesRequestUsageAndSkipsRepeatedSnapshots() throws {
        var parser = CodexLogParser()
        XCTAssertNil(parse(codexMeta(), with: &parser))
        XCTAssertNil(parse(codexTurn(), with: &parser))

        let request = codexUsage(input: 100, output: 20)
        let first = try XCTUnwrap(parse(codexTokenCount(last: request, total: request), with: &parser)?.event)
        XCTAssertNil(parse(codexTokenCount(last: request, total: request), with: &parser))
        let second = try XCTUnwrap(
            parse(
                codexTokenCount(last: codexUsage(input: 150, output: 30), total: codexUsage(input: 250, output: 50)),
                with: &parser
            )?.event
        )

        XCTAssertEqual(first.usage.processedTokens, 120)
        XCTAssertEqual(second.usage.processedTokens, 180)
        XCTAssertEqual(second.usage.modelTurn?.reasoningEffort, "high")
    }

    func testCodexValidRequestSurvivesAnIncompletePreviousTokenCount() throws {
        var parser = codexParserInTurn()
        let request = codexUsage(input: 100, output: 20)
        let first = try XCTUnwrap(parse(codexTokenCount(last: request, total: request), with: &parser)?.event)
        XCTAssertNil(
            parse(
                """
                {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count"}}
                """,
                with: &parser
            )
        )
        let third = try XCTUnwrap(
            parse(
                codexTokenCount(last: codexUsage(input: 50, output: 10), total: codexUsage(input: 200, output: 40)),
                with: &parser
            )?.event
        )

        XCTAssertEqual(first.usage.processedTokens + third.usage.processedTokens, 180)
    }

    func testCodexTracksCumulativeBaselineBeforeTheFirstTurnContext() throws {
        var parser = CodexLogParser()
        let baseline = codexUsage(input: 100, output: 20)
        XCTAssertNil(parse(codexMeta(), with: &parser))
        XCTAssertNil(parse(codexTokenCount(last: baseline, total: baseline), with: &parser))
        XCTAssertNil(parse(codexTurn(), with: &parser))

        let event = try XCTUnwrap(
            parse(
                codexTokenCount(last: codexUsage(input: 50, output: 10), total: codexUsage(input: 150, output: 30)),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.usage.processedTokens, 60)
    }

    func testCodexAcceptsInheritedFirstBaselineAndProviderTotal() throws {
        var parser = codexParserInTurn()

        let inherited = try XCTUnwrap(
            parse(
                codexTokenCount(
                    last: codexUsage(input: 100, output: 20, total: 130),
                    total: codexUsage(input: 600, output: 120, total: 750)
                ),
                with: &parser
            )?.event
        )
        let next = try XCTUnwrap(
            parse(
                codexTokenCount(
                    last: codexUsage(input: 50, output: 10, total: 61),
                    total: codexUsage(input: 650, output: 130, total: 811)
                ),
                with: &parser
            )?.event
        )

        XCTAssertEqual(inherited.usage.processedTokens, 130)
        XCTAssertEqual(next.usage.processedTokens, 61)
    }

    func testCodexZeroUsageSnapshotOnlyUpdatesTheCumulativeBaseline() throws {
        var parser = codexParserInTurn()
        let zero = codexUsage(input: 0, output: 0)
        let request = codexUsage(input: 50, output: 10)

        XCTAssertNil(parse(codexTokenCount(last: zero, total: zero), with: &parser))
        let event = try XCTUnwrap(parse(codexTokenCount(last: request, total: request), with: &parser)?.event)

        XCTAssertEqual(event.usage.processedTokens, 60)
    }

    func testCodexSyntheticFillIsIgnored() throws {
        var parser = codexParserInTurn(effort: "medium")
        let request = codexUsage(input: 100, output: 10)
        _ = parse(codexTokenCount(last: request, total: request), with: &parser)
        // A synthetic fill tops the total up to the 1,000-token context window without billable tokens.
        let filled = codexUsage(input: 0, output: 0, total: 1_000)
        XCTAssertNil(
            parse(
                codexTokenCount(
                    last: codexUsage(input: 0, output: 0, total: 890),
                    total: filled,
                    at: "2026-08-25T12:01:00.000Z"
                ),
                with: &parser
            )
        )
        XCTAssertNil(parse(codexTokenCount(last: codexUsage(input: 50, output: 5), total: filled), with: &parser))
        let event = try XCTUnwrap(
            parse(
                codexTokenCount(
                    last: codexUsage(input: 50, output: 5),
                    total: codexUsage(input: 50, output: 5, total: 1_055)
                ),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.usage.processedTokens, 55)
        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "medium")
    }

    func testCodexRejectsMalformedContextWindowsWithoutUpdatingBaseline() throws {
        for contextWindow in ["\"1000\"", "true", "9223372036854775808"] {
            var parser = codexParserInTurn()
            let request = codexUsage(input: 100, output: 20)
            let line = codexTokenCount(last: request, total: request)

            XCTAssertNil(
                parse(
                    line.replacingOccurrences(
                        of: "\"model_context_window\":1000",
                        with: "\"model_context_window\":\(contextWindow)"
                    ),
                    with: &parser
                )
            )
            let event = try XCTUnwrap(parse(line, with: &parser)?.event)
            XCTAssertEqual(event.usage.processedTokens, 120)
        }
    }

    func testCodexThreadSettingsDoNotOverrideTurnUsageMetadata() throws {
        var parser = codexParserInTurn()
        XCTAssertNil(
            parse(
                """
                {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-luna","reasoning_effort":"low","service_tier":"priority"}}}
                """,
                with: &parser
            )
        )
        let request = codexUsage(input: 100, output: 20)
        let event = try XCTUnwrap(parse(codexTokenCount(last: request, total: request), with: &parser)?.event)

        XCTAssertEqual(event.usage.modelTurn?.model, .named(id: "gpt-5.6-sol", name: "GPT 5.6 Sol"))
        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "high")
    }

    func testCodexPricesLoggedCacheWrites() throws {
        var parser = codexParserInTurn()
        let request = codexUsage(input: 100, output: 20, cached: 10, cacheWrite: 30)
        let event = try XCTUnwrap(parse(codexTokenCount(last: request, total: request), with: &parser)?.event)

        XCTAssertEqual(event.usage.processedTokens, 120)
        XCTAssertEqual(event.usage.costUSD, Decimal(string: "0.0010925"))
    }

    func testCodexRejectsOverflowingTokenFields() {
        var parser = codexParserInTurn()
        let overflow = """
            {"input_tokens":18446744073709551615,"cached_input_tokens":18446744073709551615,"cache_write_input_tokens":1,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":18446744073709551615}
            """

        XCTAssertNil(parse(codexTokenCount(last: overflow, total: overflow), with: &parser))
    }

    func testCodexReportsUnpricedModelsAndUnsupportedCacheWrites() {
        func outcome(model: String, cacheWrite: Int = 0) -> UsageLineOutcome? {
            var parser = codexParserInTurn(model: model)
            let request = codexUsage(input: 100, output: 20, cacheWrite: cacheWrite)
            return parse(codexTokenCount(last: request, total: request), with: &parser)
        }

        XCTAssertEqual(outcome(model: "unknown-model")?.unpricedModelID, "unknown-model")
        XCTAssertEqual(outcome(model: "gpt-5.5", cacheWrite: 1)?.unpricedModelID, "gpt-5.5")
        XCTAssertNotNil(outcome(model: "gpt-5.5")?.event)
    }

    func testCodexIdenticalRequestUsageAtTheSameTimestampCountsTwice() async throws {
        let request = codexUsage(input: 50, output: 10)
        try workspace.write(
            [
                codexMeta(),
                codexTurn(),
                codexTokenCount(last: request, total: request),
                codexTokenCount(last: request, total: codexUsage(input: 100, output: 20)),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )

        let snapshot = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 120)
    }

    func testCodexFavoriteCarriesTheTurnEffort() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )

        let snapshot = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 120)
        XCTAssertEqual(
            snapshot.providers[.codex]?.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "GPT 5.6 Sol", reasoningEffort: "high")
        )
    }

    func testCodexQuotesMatchPublishedRates() throws {
        let short = codexTokenUsage(uncached: 100_000, cached: 100_000, cacheWrite: 50_000, output: 10_000)
        let long = codexTokenUsage(uncached: 122_001, cached: 100_000, cacheWrite: 50_000, output: 10_000)
        let shortWithoutWrites = codexTokenUsage(uncached: 150_000, cached: 100_000, output: 10_000)
        let longWithoutWrites = codexTokenUsage(uncached: 172_001, cached: 100_000, output: 10_000)

        for (model, name, tokens, expectedUSD) in [
            ("gpt-6-astra", "GPT 6 Astra", short, "2.225"),
            ("gpt-6-astra", "GPT 6 Astra", long, "4.64002"),
            ("gpt-6-sol", "GPT 6 Sol", short, "0.445"),
            ("gpt-6-sol", "GPT 6 Sol", long, "0.928004"),
            ("gpt-6-luna", "GPT 6 Luna", short, "0.02225"),
            ("gpt-6-luna", "GPT 6 Luna", long, "0.0464002"),
            ("gpt-daybreak-blue-latest", "Daybreak Blue", short, "1.1625"),
            ("gpt-daybreak-blue-latest", "Daybreak Blue", long, "2.39501"),
            ("gpt-5.6-sol", "GPT 5.6 Sol", short, "1.1625"),
            ("gpt-5.6-sol", "GPT 5.6 Sol", long, "2.39501"),
            ("gpt-5.6-terra", "GPT 5.6 Terra", short, "0.465"),
            ("gpt-5.6-terra", "GPT 5.6 Terra", long, "0.958004"),
            ("gpt-5.6-luna", "GPT 5.6 Luna", short, "0.0465"),
            ("gpt-5.6-luna", "GPT 5.6 Luna", long, "0.0958004"),
            ("gpt-5.5", "GPT 5.5", shortWithoutWrites, "1.1"),
            ("gpt-5.5", "GPT 5.5", longWithoutWrites, "2.27001"),
            ("gpt-5.4", "GPT 5.4", shortWithoutWrites, "0.55"),
            ("gpt-5.4", "GPT 5.4", longWithoutWrites, "1.135005"),
            ("gpt-5.4-mini", "GPT 5.4 Mini", shortWithoutWrites, "0.165"),
            ("gpt-5.4-mini", "GPT 5.4 Mini", longWithoutWrites, "0.18150075"),
            ("gpt-5.3-codex", "GPT 5.3 Codex", shortWithoutWrites, "0.42"),
            ("gpt-5.3-codex", "GPT 5.3 Codex", longWithoutWrites, "0.45850175"),
        ] {
            let quote = try XCTUnwrap(CodexUsagePricing.quote(model: model, tokens: tokens), model)
            XCTAssertEqual(quote.model, .named(id: model, name: name))
            XCTAssertEqual(quote.costUSD, Decimal(string: expectedUSD), model)
        }
    }

    func testCodexLongContextRatesApplyToTheWholeRequest() throws {
        let atBoundary = try XCTUnwrap(
            CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: codexTokenUsage(uncached: 272_000))
        )
        let long = try XCTUnwrap(
            CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: codexTokenUsage(uncached: 272_001))
        )

        XCTAssertEqual(atBoundary.costUSD, Decimal(string: "1.36"))
        XCTAssertEqual(long.costUSD, Decimal(string: "2.72001"))
    }

    func testCodexAliasResolvesToCanonicalModel() throws {
        let tokens = codexTokenUsage(uncached: 1)
        let canonical = try XCTUnwrap(CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: tokens))
        let alias = try XCTUnwrap(CodexUsagePricing.quote(model: "gpt-5.6", tokens: tokens))

        XCTAssertEqual(alias.model, canonical.model)
    }
}

/// A parser that has read the session meta and a turn context, so token counts become events.
private func codexParserInTurn(model: String = "gpt-5.6-sol", effort: String = "high") -> CodexLogParser {
    var parser = CodexLogParser()
    _ = parse(codexMeta(), with: &parser)
    _ = parse(codexTurn(model: model, effort: effort), with: &parser)
    return parser
}

private func codexTokenUsage(
    uncached: UInt64,
    cached: UInt64 = 0,
    cacheWrite: UInt64 = 0,
    output: UInt64 = 0
) -> CodexTokenUsage {
    guard
        let usage = CodexTokenUsage(
            input: uncached + cached + cacheWrite,
            cachedInput: cached,
            cacheWrite: cacheWrite,
            output: output,
            reasoningOutput: 0,
            processed: uncached + cached + cacheWrite + output
        )
    else {
        preconditionFailure("invalid codex usage fixture")
    }
    return usage
}
