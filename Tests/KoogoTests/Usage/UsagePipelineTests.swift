import Foundation
import XCTest

@testable import Koogo

final class UsagePipelineTests: UsageWorkspaceTestCase {
    func testColdScanLoadsEveryFileAcrossReaderBatches() async throws {
        let usage = codexUsage(input: 100, output: 20)
        for index in 0..<19 {
            try workspace.write(
                [
                    codexTurn(id: "turn-\(index)"),
                    codexTokenCount(last: usage, total: usage),
                    "",
                ].joined(separator: "\n"),
                to: workspace.codexSessions.appending(path: "session-\(index).jsonl")
            )
        }
        let service = makePipeline()

        let report = await service.run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 19)
        XCTAssertEqual(report.ingestion.events[.codex], 19)
        XCTAssertEqual(report.snapshot.providers[.codex]?.today.processedTokens, 2_280)
    }

    func testUnicodeAndReservedCharactersInLogPaths() async throws {
        let log = workspace.codexSessions.appending(path: "项目 #100%/session ?.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        let initial = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(initial.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(initial.snapshot.providers[.codex]?.today.processedTokens, 120)

        try workspace.append(
            codexTokenCount(
                last: codexUsage(input: 50, output: 10),
                total: codexUsage(input: 150, output: 30)
            ) + "\n",
            to: log
        )
        let appended = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(appended.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(appended.snapshot.providers[.codex]?.today.processedTokens, 180)
    }

    func testDisabledProvidersAreNeitherScannedNorSummarized() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        try workspace.write(claudeLog(output: 40), to: workspace.claudeProjects.appending(path: "main.jsonl"))
        let service = makePipeline()

        let all = await service.run(at: now, providers: Provider.allCases)
        let codexOnly = await service.run(at: now, providers: [.codex])
        let codexAndGrok = await service.run(at: now, providers: [.codex, .grok])

        XCTAssertEqual(all.snapshot.summary.today.current.processedTokens, 170)
        XCTAssertEqual(Set(codexOnly.snapshot.providers.keys), [.codex])
        XCTAssertEqual(codexOnly.snapshot.summary.today.current.processedTokens, 120)
        XCTAssertEqual(codexOnly.ingestion.trackedFiles[.claude], 0)
        XCTAssertEqual(Set(codexAndGrok.snapshot.providers.keys), [.codex, .grok])
    }

    func testRefreshMovesRollingWindowsOnlyAtMidnight() async throws {
        for (index, timestamp) in [
            "2026-06-27T00:00:00Z",
            "2026-07-27T00:00:00Z",
            "2026-08-19T00:00:00Z",
            "2026-08-25T00:00:00Z",
        ].enumerated() {
            try workspace.write(
                codexLog(input: 1 << index, output: 0, usageTimestamp: timestamp),
                to: workspace.codexSessions.appending(path: "boundary-\(index).jsonl")
            )
        }
        let service = makePipeline()
        let current = await service.run(at: now, providers: Provider.allCases)
        let lastMillisecond = try XCTUnwrap(Date(iso8601: "2026-08-25T23:59:59.999Z"))
        let evening = await service.run(at: lastMillisecond, providers: Provider.allCases)
        let midnight = try XCTUnwrap(Date(iso8601: "2026-08-26T00:00:00Z"))
        let refreshed = await service.run(at: midnight, providers: Provider.allCases)

        XCTAssertEqual(current.ingestion.events[.codex], 4)
        XCTAssertEqual(current.snapshot.providers[.codex]?.today.processedTokens, 8)
        XCTAssertEqual(current.snapshot.providers[.codex]?.last7Days.processedTokens, 12)
        XCTAssertEqual(current.snapshot.providers[.codex]?.last30Days.processedTokens, 14)
        XCTAssertEqual(evening.snapshot, current.snapshot)
        XCTAssertEqual(refreshed.ingestion.events[.codex], 3)
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.today, UsagePeriodSnapshot())
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.last7Days.processedTokens, 8)
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.last30Days.processedTokens, 12)
        XCTAssertEqual(refreshed.snapshot.summary.last30Days.costChange, .increase(fraction: 5))
    }

    func testFavoritesChangeAtMidnightWhileOlderTurnsStayIndexed() async throws {
        for input in 1...2 {
            try workspace.write(
                codexLog(
                    input: input,
                    output: 0,
                    model: "gpt-5.6-luna",
                    usageTimestamp: "2026-07-27T00:00:00Z"
                ),
                to: workspace.codexSessions.appending(path: "first-day-\(input).jsonl")
            )
        }
        try workspace.write(
            codexLog(input: 4, output: 0, model: "gpt-5.6-sol"),
            to: workspace.codexSessions.appending(path: "recent.jsonl")
        )
        let service = makePipeline()
        let current = await service.run(at: now, providers: Provider.allCases)
        let lastMillisecond = try XCTUnwrap(Date(iso8601: "2026-08-25T23:59:59.999Z"))
        let evening = await service.run(at: lastMillisecond, providers: Provider.allCases)
        let nextMidnight = try XCTUnwrap(Date(iso8601: "2026-08-26T00:00:00Z"))
        let refreshed = await service.run(at: nextMidnight, providers: Provider.allCases)

        XCTAssertEqual(current.ingestion.events[.codex], 3)
        XCTAssertEqual(current.snapshot.providers[.codex]?.favorite?.modelName, "GPT 5.6 Luna")
        XCTAssertEqual(evening.snapshot, current.snapshot)
        XCTAssertEqual(refreshed.ingestion.events[.codex], 3)
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.favorite?.modelName, "GPT 5.6 Sol")
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.last30Days.processedTokens, 4)
    }

    func testUnpricedModelIsExcludedFromTotalsAndReported() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = makePipeline()

        let report = await service.run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.snapshot.providers[.codex]?.last30Days, UsagePeriodSnapshot())
        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.events, [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, ["unknown-model"])
    }

    func testColdScanRetainsComparisonPeriodsAndDiscardsOlderHistory() async throws {
        try workspace.write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-day",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: workspace.codexSessions.appending(path: "previous-day.jsonl")
        )
        try workspace.write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-30-days",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: workspace.codexSessions.appending(path: "previous-30-days.jsonl")
        )
        for index in 1...3 {
            try workspace.write(
                codexLog(
                    input: 1,
                    output: 0,
                    thread: "older-\(index)",
                    model: "gpt-5.6-luna",
                    usageTimestamp: "2026-06-26T23:59:59.999Z"
                ),
                to: workspace.codexSessions.appending(path: "older-\(index).jsonl")
            )
        }
        let service = makePipeline()

        let snapshot = await service.run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .decrease(fraction: Decimal(1) / 2))
        XCTAssertEqual(snapshot.providers[.codex]?.favorite?.modelName, "GPT 5.6 Sol")
    }

    func testRecordsBesideBilledOnesAreSkipped() async throws {
        let request = codexUsage(input: 100, output: 20)
        try workspace.write(
            [
                codexMeta(),
                """
                {"timestamp":"2026-08-25T11:31:00.000Z","ordinal":2,"type":"response_item","payload":{"type":"function_call","name":"token_count"}}
                """,
                """
                {"timestamp":"2026-08-25T11:32:00.000Z","ordinal":3,"type":"event_msg","payload":{"type":"item_completed","item":{}}}
                """,
                codexTurn(),
                codexTokenCount(last: request, total: request),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        try workspace.write(
            [
                """
                {"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":"assistant usage"}}
                """,
                #"{"parentUuid":"u","isSidechain":false,"attachment":{"type":"file"},"type":"attachment"}"#,
                claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":40"#),
                "",
            ].joined(separator: "\n"),
            to: workspace.claudeProjects.appending(path: "project/session.jsonl")
        )
        try workspace.write(
            [
                #"{"type":"session","version":3,"id":"session","timestamp":"2026-08-25T11:00:00.000Z"}"#,
                """
                {"type":"thinking_level_change","id":"high","parentId":null,"timestamp":"2026-08-25T11:30:00.000Z","thinkingLevel":"high"}
                """,
                #"{"type":"model_change","id":"model","parentId":"high","timestamp":"2026-08-25T11:31:00.000Z"}"#,
                """
                {"type":"message","id":"user","parentId":"model","timestamp":"2026-08-25T11:32:00.000Z","message":{"role":"user","content":[]}}
                """,
                """
                {"type":"message","id":"tool","parentId":"user","timestamp":"2026-08-25T11:33:00.000Z","message":{"role":"toolResult","content":[]}}
                """,
                piAssistant(id: "reply", parentID: "tool", model: "model-a", usage: piUsage(input: 10, cost: "0.01")),
                "",
            ].joined(separator: "\n"),
            to: workspace.piSessions.appending(path: "session.jsonl")
        )

        let report = await makePipeline().run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.malformedLines, [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.events, [.codex: 1, .claude: 1, .piAgent: 1, .grok: 0])
        XCTAssertEqual(report.snapshot.providers[.piAgent]?.favorite?.reasoningEffort, "high")
    }
}
