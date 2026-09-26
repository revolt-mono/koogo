import Foundation
import XCTest

@testable import Koogo

final class ClaudeUsageTests: UsageWorkspaceTestCase {
    func testClaudeParsesCacheDurationsSpeedGeoSearchAndMissingEffort() throws {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(
            model: "claude-opus-5",
            usage: """
                "input_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":30,"ephemeral_1h_input_tokens":40},"speed":"fast","inference_geo":"us","server_tool_use":{"web_search_requests":2}
                """
        )

        let event = try XCTUnwrap(parse(line, with: &parser)?.event)

        XCTAssertEqual(event.provider, .claude)
        XCTAssertEqual(event.usage.processedTokens, 140)
        XCTAssertEqual(event.usage.costUSD, Decimal(string: "0.0236245"))
        XCTAssertNil(event.usage.modelTurn?.reasoningEffort)
    }

    func testClaudePreservesAggregateCacheCreationWithoutInventingDuration() throws {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(
            model: "claude-opus-5",
            usage: #""input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40"#
        )

        let event = try XCTUnwrap(parse(line, with: &parser)?.event)

        XCTAssertEqual(event.usage.processedTokens, 120)
        XCTAssertEqual(event.usage.costUSD, Decimal(string: "0.0014875"))
    }

    func testClaudeRejectsInconsistentCacheSplit() {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(
            model: "claude-opus-5",
            usage: """
                "input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":40}
                """
        )

        XCTAssertNil(parse(line, with: &parser))
    }

    func testClaudeRejectsRecordsWithoutBothStableIDs() {
        var parser = ClaudeLogParser()
        let line = """
            {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":40}}}
            """

        XCTAssertNil(parse(line, with: &parser))
    }

    func testClaudeRejectsOverflowingTokenFields() {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(
            model: "claude-opus-5",
            usage: """
                "input_tokens":0,"cache_creation_input_tokens":18446744073709551615,"output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":18446744073709551615,"ephemeral_1h_input_tokens":1}
                """
        )

        XCTAssertNil(parse(line, with: &parser))
    }

    func testClaudeReportsUnpricedModelsAndBilledOptions() {
        for (model, usage) in [
            ("unknown-model", #""input_tokens":10,"output_tokens":40"#),
            ("claude-sonnet-4-6", #""input_tokens":10,"output_tokens":40,"speed":"fast""#),
            ("claude-haiku-4-5", #""input_tokens":10,"output_tokens":40,"inference_geo":"us""#),
            ("claude-opus-5", #""input_tokens":10,"output_tokens":40,"speed":"turbo""#),
        ] {
            var parser = ClaudeLogParser()
            let outcome = parse(claudeAssistant(model: model, usage: usage), with: &parser)

            XCTAssertEqual(outcome?.unpricedModelID, model)
        }
    }

    func testClaudeCopyWithMoreExplicitMetadataWinsAtEqualOutput() throws {
        let tokens = #""input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40"#
        // One more input token lets the bare copy win any revision tie.
        let bare = claudeAssistant(
            model: "claude-opus-5",
            usage: #""input_tokens":11,"cache_creation_input_tokens":70,"output_tokens":40"#
        )

        for detailed in [
            claudeAssistant(model: "claude-opus-5", usage: tokens + #","speed":"standard""#),
            claudeAssistant(
                model: "claude-opus-5",
                usage: tokens + #","cache_creation":{"ephemeral_5m_input_tokens":70}"#
            ),
            claudeAssistant(model: "claude-opus-5", usage: tokens, effort: "high"),
        ] {
            var parser = ClaudeLogParser()
            let bareCopy = try XCTUnwrap(parse(bare, with: &parser)?.event)
            let detailedCopy = try XCTUnwrap(parse(detailed, with: &parser)?.event)

            for copies in [[bareCopy, detailedCopy], [detailedCopy, bareCopy]] {
                var index = UsageEventIndex(since: .distantPast)
                for copy in copies {
                    index.insert(.event(copy))
                }
                XCTAssertEqual(index.values.map(\.usage.processedTokens), [120], detailed)
            }
        }
    }

    func testColdScanDeduplicatesClaudePartialsAndCopies() async throws {
        try workspace.write(claudeLog(output: 2), to: workspace.claudeProjects.appending(path: "project/main.jsonl"))
        try workspace.write(
            claudeLog(output: 40),
            to: workspace.claudeProjects.appending(path: "project/agent/copy.jsonl")
        )

        let snapshot = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.claude]?.today.processedTokens, 50)
        XCTAssertEqual(
            snapshot.providers[.claude]?.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "Opus 5", reasoningEffort: nil)
        )
    }

    func testClaudeQuotesMatchPublishedRates() throws {
        let usage = { (isFast: Bool, isUSInference: Bool) in
            claudeBillableUsage(
                uncachedInput: 100_000,
                cachedInput: 100_000,
                cacheWrite5MinuteInput: 100_000,
                cacheWrite1HourInput: 100_000,
                output: 10_000,
                isFast: isFast,
                isUSInference: isUSInference
            )
        }
        let standard = usage(false, false)
        let fast = usage(true, false)
        let usInference = usage(false, true)

        for (model, name, usage, expectedUSD) in [
            ("claude-fable-5-1", "Fable 5.1", standard, "4.775"),
            ("claude-mythos-5-1", "Mythos 5.1", standard, "4.775"),
            ("claude-fable-5", "Fable 5", standard, "4.85"),
            ("claude-mythos-5", "Mythos 5", standard, "4.85"),
            ("claude-opus-5-5", "Opus 5.5", standard, "1.92"),
            ("claude-opus-5-5", "Opus 5.5", fast, "3.84"),
            ("claude-opus-5", "Opus 5", standard, "2.425"),
            ("claude-opus-5", "Opus 5", fast, "4.85"),
            ("claude-opus-4-8", "Opus 4.8", standard, "2.425"),
            ("claude-opus-4-8", "Opus 4.8", fast, "4.85"),
            ("claude-opus-4-7", "Opus 4.7", standard, "2.425"),
            ("claude-opus-4-6", "Opus 4.6", standard, "2.425"),
            ("claude-opus-4-5-20251101", "Opus 4.5", standard, "2.425"),
            ("claude-sonnet-5", "Sonnet 5", standard, "0.97"),
            ("claude-sonnet-5", "Sonnet 5", usInference, "1.067"),
            ("claude-sonnet-4-6", "Sonnet 4.6", standard, "1.455"),
            ("claude-sonnet-4-5-20250929", "Sonnet 4.5", standard, "1.455"),
            ("claude-haiku-4-5-20251001", "Haiku 4.5", standard, "0.485"),
        ] {
            let quote = try XCTUnwrap(ClaudeUsagePricing.quote(model: model, usage: usage), model)
            XCTAssertEqual(quote.model, .named(id: model, name: name))
            XCTAssertEqual(quote.costUSD, Decimal(string: expectedUSD), model)
        }
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
        XCTAssertEqual(alias.model, .named(id: "claude-sonnet-4-5-20250929", name: "Sonnet 4.5"))
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
}

private func claudeBillableUsage(
    uncachedInput: UInt64 = 0,
    cachedInput: UInt64 = 0,
    cacheWrite5MinuteInput: UInt64 = 0,
    cacheWrite1HourInput: UInt64 = 0,
    output: UInt64 = 0,
    isFast: Bool = false,
    isUSInference: Bool = false
) -> ClaudeBillableUsage {
    guard
        let tokens = ClaudeTokenUsage(
            input: uncachedInput,
            cacheRead: cachedInput,
            cacheCreation: .byDuration(
                fiveMinute: cacheWrite5MinuteInput,
                oneHour: cacheWrite1HourInput
            ),
            output: output
        )
    else {
        preconditionFailure("invalid claude usage fixture")
    }
    return ClaudeBillableUsage(tokens: tokens, isFast: isFast, isUSInference: isUSInference, webSearchRequests: 0)
}
