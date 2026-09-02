import Foundation
import XCTest

@testable import Koogo

final class UsageServiceTests: UsageWorkspaceTestCase {
    func testColdScanDeduplicatesClaudePartialsAndProviderSnapshots() async throws {
        let codex = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: codex)

        let claudeMain = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let claudeCopy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try workspace.write(claudeLog(output: 2), to: claudeMain)
        try workspace.write(claudeLog(output: 40), to: claudeCopy)

        let service = UsageService(locations: locations, calendar: calendar)
        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
        XCTAssertEqual(
            snapshot.codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Sol",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(snapshot.claude.today.processedTokens, 50)
        XCTAssertEqual(
            snapshot.claude.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "Opus 5",
                reasoningEffort: nil
            )
        )
    }

    func testRefreshRebuildsSnapshotForNewDay() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let service = UsageService(locations: locations, calendar: calendar)
        let current = await service.refresh(at: now).snapshot

        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let refreshed = await service.refresh(at: nextDay).snapshot

        XCTAssertEqual(current.codex.today.processedTokens, 120)
        XCTAssertEqual(refreshed.codex.today, UsagePeriodSnapshot())
        XCTAssertEqual(refreshed.codex.week.processedTokens, 120)
    }

    func testUnknownModelIsIgnoredCompletely() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.snapshot.codex.month, UsagePeriodSnapshot())
        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0])
        XCTAssertEqual(report.ingestion.events, [.codex: 0, .claude: 0, .piAgent: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, ["unknown-model"])
    }

    func testUnpricedModelsOutsideTheHistoryWindowAreNotReported() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(
            codexLog(
                input: 100,
                output: 20,
                model: "unknown-model",
                usageTimestamp: "2026-05-01T12:00:00.000Z"
            ),
            to: log
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, [])
    }

    func testCodexIdenticalRequestUsageAtTheSameTimestampCountsTwice() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let timestamp = "2026-08-25T12:00:00.000Z"
        let contents = [
            codexSessionMetadata(thread: "thread"),
            codexTurnContext(model: "gpt-5.6-sol"),
            codexToken(
                timestamp: timestamp,
                lastInput: 50,
                lastOutput: 10,
                totalInput: 50,
                totalOutput: 10
            ),
            codexToken(
                timestamp: timestamp,
                lastInput: 50,
                lastOutput: 10,
                totalInput: 100,
                totalOutput: 20
            ),
            "",
        ].joined(separator: "\n")
        try workspace.write(contents, to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testFileLastWrittenBeforeHistoryWindowIsSkippedUntilAppended() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let skipped = await service.refresh(at: now)
        XCTAssertEqual(skipped.ingestion.trackedFiles[.codex], 0)
        XCTAssertEqual(skipped.snapshot.codex.today, UsagePeriodSnapshot())

        try workspace.append(
            codexToken(
                timestamp: "2026-08-25T13:00:00.000Z",
                lastInput: 50,
                lastOutput: 10,
                totalInput: 150,
                totalOutput: 30
            ) + "\n",
            to: log
        )
        let appended = await service.refresh(at: now)
        XCTAssertEqual(appended.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(appended.snapshot.codex.today.processedTokens, 180)
    }

    func testColdScanRetainsComparisonPeriodsAndDiscardsOlderHistory() async throws {
        try workspace.write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-day",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-day.jsonl")
        )
        try workspace.write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-month",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-month.jsonl")
        )
        for index in 1...3 {
            try workspace.write(
                codexLog(
                    input: 1,
                    output: 0,
                    thread: "older-\(index)",
                    model: "gpt-5.6-luna",
                    usageTimestamp: "2026-06-30T17:00:00.000Z"
                ),
                to: locations.logs.codex.sessions.appending(path: "older-\(index).jsonl")
            )
        }
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.month.costChange, .decrease(fraction: Decimal(1) / 2))
        XCTAssertEqual(snapshot.codex.favorite?.modelName, "GPT 5.6 Sol")
    }

    func testClaudePartialsAndCopiesWithoutStableIDsAreIgnored() async throws {
        let partial = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let copy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try workspace.write(claudeLog(output: 2, requestID: nil), to: partial)
        try workspace.write(claudeLog(output: 40, requestID: nil), to: copy)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.claude.month, UsagePeriodSnapshot())
    }
}
