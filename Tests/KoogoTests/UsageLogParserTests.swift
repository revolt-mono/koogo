import Foundation
import XCTest

@testable import Koogo

final class UsageLogParserTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testCodexUsesRequestUsageAndSkipsRepeatedSnapshots() throws {
        var parser = UsageFileParserState.codex()
        XCTAssertNil(parse(codexMeta(), with: &parser))
        XCTAssertNil(parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser))

        let first = try XCTUnwrap(
            parse(codexToken(last: usage(100, 20), total: usage(100, 20)), with: &parser)
        )
        XCTAssertNil(parse(codexToken(last: usage(100, 20), total: usage(100, 20)), with: &parser))
        let second = try XCTUnwrap(
            parse(codexToken(last: usage(150, 30), total: usage(250, 50)), with: &parser)
        )

        XCTAssertEqual(first.usage.processedTokens, 120)
        XCTAssertEqual(second.usage.processedTokens, 180)
        XCTAssertEqual(second.usage.modelTurn?.reasoningEffort, "high")
    }

    func testCodexValidRequestSurvivesAnIncompletePreviousTokenCount() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser)
        let first = try XCTUnwrap(
            parse(codexToken(last: usage(100, 20), total: usage(100, 20)), with: &parser)
        )
        XCTAssertNil(
            parse(
                """
                {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count"}}
                """,
                with: &parser
            )
        )
        let third = try XCTUnwrap(
            parse(codexToken(last: usage(50, 10), total: usage(200, 40)), with: &parser)
        )

        XCTAssertEqual(first.usage.processedTokens + third.usage.processedTokens, 180)
    }

    func testCodexTracksCumulativeBaselineBeforeTheFirstTurnContext() throws {
        var parser = UsageFileParserState.codex()
        XCTAssertNil(parse(codexMeta(), with: &parser))
        XCTAssertNil(parse(codexToken(last: usage(100, 20), total: usage(100, 20)), with: &parser))
        XCTAssertNil(parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser))

        let event = try XCTUnwrap(
            parse(codexToken(last: usage(50, 10), total: usage(150, 30)), with: &parser)
        )

        XCTAssertEqual(event.usage.processedTokens, 60)
    }

    func testCodexAcceptsInheritedFirstBaselineAndProviderTotal() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser)

        let inherited = try XCTUnwrap(
            parse(
                codexToken(
                    last: usage(100, 20, total: 130),
                    total: usage(600, 120, total: 750)
                ),
                with: &parser
            )
        )
        let next = try XCTUnwrap(
            parse(
                codexToken(
                    last: usage(50, 10, total: 61),
                    total: usage(650, 130, total: 811)
                ),
                with: &parser
            )
        )

        XCTAssertEqual(inherited.usage.processedTokens, 130)
        XCTAssertEqual(next.usage.processedTokens, 61)
    }

    func testCodexZeroUsageSnapshotOnlyUpdatesTheCumulativeBaseline() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser)

        XCTAssertNil(parse(codexToken(last: usage(0, 0), total: usage(0, 0)), with: &parser))
        let event = try XCTUnwrap(
            parse(codexToken(last: usage(50, 10), total: usage(50, 10)), with: &parser)
        )

        XCTAssertEqual(event.usage.processedTokens, 60)
    }

    func testCodexSyntheticFillIsIgnored() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "medium"), with: &parser)
        _ = parse(codexToken(last: usage(100, 10), total: usage(100, 10)), with: &parser)
        XCTAssertNil(parse(codexSyntheticFill(contextWindow: 1_000, previousTotal: 110), with: &parser))
        let event = try XCTUnwrap(
            parse(codexToken(last: usage(50, 5), total: usage(50, 5, total: 1_055)), with: &parser)
        )

        XCTAssertEqual(event.usage.processedTokens, 55)
        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "medium")
    }

    func testCodexThreadSettingsDoNotOverrideTurnUsageMetadata() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser)
        XCTAssertNil(
            parse(
                """
                {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-luna","reasoning_effort":"low","service_tier":"priority"}}}
                """,
                with: &parser
            )
        )
        let event = try XCTUnwrap(
            parse(codexToken(last: usage(100, 20), total: usage(100, 20)), with: &parser)
        )

        XCTAssertEqual(
            event.usage.modelTurn?.model,
            .codex(id: "gpt-5.6-sol", name: "GPT 5.6 Sol")
        )
        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "high")
    }

    func testCodexPreservesCacheWritesWithoutInventingDuration() throws {
        var parser = UsageFileParserState.codex()
        _ = parse(codexMeta(), with: &parser)
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &parser)
        let event = try XCTUnwrap(
            parse(
                codexToken(
                    last: usage(100, 20, cached: 10, cacheWrite: 30),
                    total: usage(100, 20, cached: 10, cacheWrite: 30)
                ),
                with: &parser
            )
        )
        guard case .codex(let id, _) = event else {
            return XCTFail("unexpected event provider")
        }

        XCTAssertEqual(
            id.tokens,
            try XCTUnwrap(
                CodexTokenUsage(
                    input: 100,
                    cachedInput: 10,
                    cacheWrite: 30,
                    output: 20,
                    reasoningOutput: 0,
                    processed: 120
                )
            )
        )
        XCTAssertEqual(id.tokens.uncachedInput, 60)
    }

    func testClaudeParsesCacheDurationsSpeedGeoSearchAndMissingEffort() throws {
        var parser = UsageFileParserState.claude
        let line = """
            {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":30,"ephemeral_1h_input_tokens":40},"speed":"fast","inference_geo":"us","server_tool_use":{"web_search_requests":2}}}}
            """

        let event = try XCTUnwrap(parse(line, with: &parser))

        XCTAssertEqual(event.provider, .claude)
        XCTAssertEqual(event.usage.processedTokens, 140)
        XCTAssertEqual(event.usage.costUSD, Decimal(string: "0.0236245"))
        XCTAssertNil(event.usage.modelTurn?.reasoningEffort)
    }

    func testClaudePreservesAggregateCacheCreationWithoutInventingDuration() throws {
        var parser = UsageFileParserState.claude
        let event = try XCTUnwrap(
            parse(
                """
                {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40}}}
                """,
                with: &parser
            )
        )
        XCTAssertEqual(event.usage.processedTokens, 120)
        XCTAssertEqual(event.usage.costUSD, Decimal(string: "0.0014875"))
    }

    func testClaudeRejectsInconsistentCacheSplit() {
        var parser = UsageFileParserState.claude
        let line = """
            {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":40}}}}
            """

        XCTAssertNil(parse(line, with: &parser))
    }

    func testClaudeRejectsRecordsWithoutBothStableIDs() {
        var parser = UsageFileParserState.claude
        let line = """
            {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":40}}}
            """

        XCTAssertNil(parse(line, with: &parser))
    }

    func testOverflowingTokenFieldsAreRejected() {
        var codexParser = UsageFileParserState.codex()
        _ = parse(codexTurn(model: "gpt-5.6-sol", effort: "high"), with: &codexParser)
        let codex = """
            {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":18446744073709551615,"cached_input_tokens":18446744073709551615,"cache_write_input_tokens":1,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":18446744073709551615},"total_token_usage":{"input_tokens":18446744073709551615,"cached_input_tokens":18446744073709551615,"cache_write_input_tokens":1,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":18446744073709551615},"model_context_window":1000}}}
            """
        XCTAssertNil(parse(codex, with: &codexParser))

        var claudeParser = UsageFileParserState.claude
        let claude = """
            {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":0,"cache_creation_input_tokens":18446744073709551615,"output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":18446744073709551615,"ephemeral_1h_input_tokens":1}}}}
            """
        XCTAssertNil(parse(claude, with: &claudeParser))
    }

    private func parse(_ line: String, with parser: inout UsageFileParserState) -> UsageEvent? {
        Data(line.utf8).withUnsafeBytes {
            parser.parse($0, decoder: decoder)
        }
    }

    private func codexMeta() -> String {
        """
        {"timestamp":"2026-08-25T11:59:00.000Z","type":"session_meta","payload":{"id":"thread"}}
        """
    }

    private func codexTurn(model: String, effort: String) -> String {
        """
        {"timestamp":"2026-08-25T11:59:30.000Z","type":"turn_context","payload":{"turn_id":"turn","model":"\(model)","effort":"\(effort)"}}
        """
    }

    private func codexToken(last: String, total: String) -> String {
        """
        {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":\(last),"total_token_usage":\(total),"model_context_window":1000}}}
        """
    }

    private func codexSyntheticFill(contextWindow: Int, previousTotal: Int) -> String {
        """
        {"timestamp":"2026-08-25T12:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":\(usage(0, 0, total: contextWindow - previousTotal)),"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":\(contextWindow)},"model_context_window":\(contextWindow)}}}
        """
    }

    private func usage(
        _ input: Int,
        _ output: Int,
        cached: Int = 0,
        cacheWrite: Int = 0,
        total: Int? = nil
    ) -> String {
        """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":\(cacheWrite),"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(total ?? input + output)}
        """
    }
}
