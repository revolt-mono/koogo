import Foundation
import XCTest

@testable import Koogo

final class CodexUsageTests: UsageWorkspaceTestCase {
    func testCodexBillsEachResponseRecordUnderTheTurnModel() throws {
        var parser = CodexUsageLogParser()
        XCTAssertNil(try parse(codexMeta(), with: &parser))
        XCTAssertNil(try parse(codexTurn(), with: &parser))

        let request = codexUsage(input: 100, output: 20)
        let first = try XCTUnwrap(parse(codexTokenUsageRecord(request, thread: request), with: &parser)?.event)
        let second = try XCTUnwrap(
            try parse(
                codexTokenUsageRecord(codexUsage(input: 150, output: 30), thread: codexUsage(input: 250, output: 50)),
                with: &parser
            )?.event
        )

        XCTAssertEqual(first.record.processedTokens, 120)
        XCTAssertEqual(second.record.processedTokens, 180)
        XCTAssertEqual(second.record.model, ModelID("gpt-5.6-sol"))
        XCTAssertNotEqual(first.id, second.id)
    }

    func testCodexRecordsBeforeTheFirstTurnContextAreSkipped() throws {
        var parser = CodexUsageLogParser()
        let request = codexUsage(input: 100, output: 20)
        XCTAssertNil(try parse(codexMeta(), with: &parser))
        XCTAssertNil(try parse(codexTokenUsageRecord(request, thread: request), with: &parser))
        XCTAssertNil(try parse(codexTurn(), with: &parser))

        let event = try XCTUnwrap(
            try parse(
                codexTokenUsageRecord(codexUsage(input: 50, output: 10), thread: codexUsage(input: 150, output: 30)),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.record.processedTokens, 60)
    }

    func testMalformedTurnContextsDoNotReuseThePreviousModel() async throws {
        for context in [
            #"{"type":"turn_context"}"#,
            #"{"type":"turn_context","payload":null}"#,
            #"{"type":"turn_context","payload":{}}"#,
            #"{"type":"turn_context","payload":{"model":12}}"#,
            #"{"type":"turn_context","payload":{"model":""}}"#,
        ] {
            let request = codexUsage(input: 100, output: 20)
            try workspace.write(
                [
                    codexLog(input: 100, output: 20, turn: "before"),
                    context,
                    codexTokenUsageRecord(request, thread: request, turn: "invalid"),
                    codexLog(input: 50, output: 10, turn: "after", model: "gpt-6-luna"),
                ].joined(separator: "\n"),
                to: workspace.codexSessions.appending(path: "session.jsonl")
            )

            let report = await makePipeline().run(at: usageTestTimestamp, providers: [.codex])

            XCTAssertEqual(report.ingestion.malformedLines[.codex], 1, context)
            XCTAssertTrue(report.ingestion.unpricedModels.isEmpty, context)
            XCTAssertEqual(report.ingestion.events[.codex], 2, context)
            XCTAssertEqual(report.snapshot.todayTokens(.codex), 180, context)
            XCTAssertEqual(
                report.snapshot.providers[.codex]?.periods[.today].total.cost.usd,
                Decimal(string: "0.00111"),
                context
            )
        }
    }

    func testCodexUsesTheResponseUsageWhenTheThreadTotalIsInherited() throws {
        var parser = try codexParserInTurn()

        let inherited = try XCTUnwrap(
            try parse(
                codexTokenUsageRecord(
                    codexUsage(input: 100, output: 20, total: 130),
                    thread: codexUsage(input: 600, output: 120, total: 750)
                ),
                with: &parser
            )?.event
        )
        let next = try XCTUnwrap(
            try parse(
                codexTokenUsageRecord(
                    codexUsage(input: 50, output: 10, total: 61),
                    thread: codexUsage(input: 650, output: 130, total: 811)
                ),
                with: &parser
            )?.event
        )

        XCTAssertEqual(inherited.record.processedTokens, 130)
        XCTAssertEqual(next.record.processedTokens, 61)
    }

    func testCodexRejectsRecordsMissingUsageOrTimestamp() throws {
        var parser = try codexParserInTurn()
        let request = codexUsage(input: 100, output: 20)
        let record = codexTokenUsageRecord(request, thread: request)
        let undated = record.replacingOccurrences(of: #""timestamp":"\#(usageTestTimestampText)","#, with: "")
        var outsideTurn = CodexUsageLogParser()

        XCTAssertThrowsError(
            try parse(record.replacingOccurrences(of: #""usage":\#(request),"#, with: ""), with: &parser)
        )
        XCTAssertThrowsError(try parse(undated, with: &parser))
        XCTAssertThrowsError(try parse(undated, with: &outsideTurn))
        XCTAssertEqual(try parse(record, with: &parser)?.event?.record.processedTokens, 120)
    }

    func testCodexRejectsMalformedOutputTokens() throws {
        for outputTokens in ["\"20\"", "true", "18446744073709551616"] {
            var parser = try codexParserInTurn()
            let request = codexUsage(input: 100, output: 20)
            let line = codexTokenUsageRecord(request, thread: request)

            XCTAssertThrowsError(
                try parse(
                    line.replacingOccurrences(of: "\"output_tokens\":20", with: "\"output_tokens\":\(outputTokens)"),
                    with: &parser
                )
            )
            let event = try XCTUnwrap(parse(line, with: &parser)?.event)
            XCTAssertEqual(event.record.processedTokens, 120)
        }
    }

    func testCodexThreadSettingsDoNotOverrideTurnUsageMetadata() throws {
        var parser = try codexParserInTurn()
        XCTAssertNil(
            try parse(
                """
                {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-luna","reasoning_effort":"low","service_tier":"priority"}}}
                """,
                with: &parser
            )
        )
        let request = codexUsage(input: 100, output: 20)
        let event = try XCTUnwrap(parse(codexTokenUsageRecord(request, thread: request), with: &parser)?.event)

        XCTAssertEqual(event.record.model, ModelID("gpt-5.6-sol"))
    }

    func testCodexPricesLoggedCacheWrites() throws {
        for (model, expectedUSD) in [
            ("gpt-5.6-sol", "0.0010925"),
            ("gpt-6.1-sol", "0.000396"),
        ] {
            var parser = try codexParserInTurn(model: model)
            let request = codexUsage(input: 100, output: 20, cached: 10, cacheWrite: 30)
            let event = try XCTUnwrap(parse(codexTokenUsageRecord(request, thread: request), with: &parser)?.event)

            XCTAssertEqual(event.record.processedTokens, 120)
            XCTAssertEqual(event.record.model?.rawValue, model)
            XCTAssertEqual(event.record.cost.usd, Decimal(string: expectedUSD), model)
        }
    }

    func testCodexRejectsOverflowingTokenFields() throws {
        var parser = try codexParserInTurn()
        let overflow = """
            {"input_tokens":18446744073709551615,"cached_input_tokens":18446744073709551615,"cache_write_input_tokens":1,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":18446744073709551615}
            """

        XCTAssertThrowsError(try parse(codexTokenUsageRecord(overflow, thread: overflow), with: &parser))
    }

    func testCodexReportsUnpricedModelsAndUnsupportedCacheWrites() throws {
        func outcome(model: String, cacheWrite: Int = 0) throws -> UsageLineOutcome? {
            var parser = try codexParserInTurn(model: model)
            let request = codexUsage(input: 100, output: 20, cacheWrite: cacheWrite)
            return try parse(codexTokenUsageRecord(request, thread: request), with: &parser)
        }

        XCTAssertEqual(try outcome(model: "unknown-model")?.unpricedModel, "unknown-model")
        XCTAssertEqual(try outcome(model: "gpt-5.5", cacheWrite: 1)?.unpricedModel, "gpt-5.5")
        XCTAssertNotNil(try outcome(model: "gpt-5.5")?.event)
    }

    func testCodexIdenticalRequestUsageAtTheSameTimestampCountsTwice() async throws {
        let request = codexUsage(input: 50, output: 10)
        try workspace.write(
            [
                codexMeta(),
                codexTurn(),
                codexTokenUsageRecord(request, thread: request),
                codexTokenUsageRecord(request, thread: codexUsage(input: 100, output: 20)),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )

        let snapshot = await makePipeline().run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.todayTokens(.codex), 120)
    }

    func testCodexQuotesMatchPublishedRates() throws {
        let short = codexTokenUsage(uncached: 100_000, cached: 100_000, cacheWrite: 50_000, output: 10_000)
        let long = codexTokenUsage(uncached: 122_001, cached: 100_000, cacheWrite: 50_000, output: 10_000)
        let shortWithoutWrites = codexTokenUsage(uncached: 150_000, cached: 100_000, output: 10_000)
        let longWithoutWrites = codexTokenUsage(uncached: 172_001, cached: 100_000, output: 10_000)

        for (model, name, tokens, expectedUSD) in [
            ("gpt-6.1-sol", "GPT 6.1 Sol", short, "0.435"),
            ("gpt-6.1-sol", "GPT 6.1 Sol", long, "0.908004"),
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
            let quote = try XCTUnwrap(CodexUsagePricing.quote(model: ModelID(model), tokens: tokens), model)
            XCTAssertEqual(quote.model, ModelID(model))
            XCTAssertEqual(CodexUsagePricing.displayName(of: quote.model), name)
            XCTAssertEqual(quote.cost.usd, Decimal(string: expectedUSD), model)
        }
    }

    func testCodexLongContextRatesApplyToTheWholeRequest() throws {
        let atBoundary = try XCTUnwrap(
            CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: codexTokenUsage(uncached: 272_000))
        )
        let long = try XCTUnwrap(
            CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: codexTokenUsage(uncached: 272_001))
        )

        XCTAssertEqual(atBoundary.cost.usd, Decimal(string: "1.36"))
        XCTAssertEqual(long.cost.usd, Decimal(string: "2.72001"))
    }

    func testCodexAliasResolvesToCanonicalModel() throws {
        let tokens = codexTokenUsage(uncached: 1)
        let canonical = try XCTUnwrap(CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: tokens))
        let alias = try XCTUnwrap(CodexUsagePricing.quote(model: "gpt-5.6", tokens: tokens))

        XCTAssertEqual(alias.model, canonical.model)
    }
}

private func codexParserInTurn(model: String = "gpt-5.6-sol") throws -> CodexUsageLogParser {
    var parser = CodexUsageLogParser()
    _ = try parse(codexMeta(), with: &parser)
    _ = try parse(codexTurn(model: model), with: &parser)
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
            processed: uncached + cached + cacheWrite + output
        )
    else {
        preconditionFailure("invalid codex usage fixture")
    }
    return usage
}
