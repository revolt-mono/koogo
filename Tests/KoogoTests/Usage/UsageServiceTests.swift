import Foundation
import XCTest

@testable import Koogo

final class UsageServiceTests: XCTestCase {
    private var workspace: UsageTestWorkspace!
    private let now = usageTestTimestamp

    private var root: URL { workspace.root }
    private var locations: UsageLocations { workspace.locations }
    private var calendar: Calendar { workspace.calendar }

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    func testColdScanDeduplicatesClaudePartialsAndProviderSnapshots() async throws {
        let codex = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: codex)

        let claudeMain = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let claudeCopy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2), to: claudeMain)
        try write(claudeLog(output: 40), to: claudeCopy)

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

    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        let appended = codexToken(
            timestamp: "2026-08-25T13:00:00.000Z",
            lastInput: 50,
            lastOutput: 10,
            totalInput: 150,
            totalOutput: 30
        )
        try append(appended, to: log)
        let beforeNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(beforeNewline.codex.today.processedTokens, 120)

        try append("\n", to: log)
        let afterNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(afterNewline.codex.today.processedTokens, 180)
    }

    func testRefreshRebuildsSnapshotForNewDay() async throws {
        try write(
            codexLog(input: 100, output: 20),
            to: locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let service = UsageService(locations: locations, calendar: calendar)
        let current = await service.refresh(at: now).snapshot

        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let refreshed = await service.refresh(at: nextDay).snapshot

        XCTAssertEqual(current.codex.today.processedTokens, 120)
        XCTAssertEqual(refreshed.codex.today, .zero)
        XCTAssertEqual(refreshed.codex.week.processedTokens, 120)
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try write(contents, to: active)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        let archived = locations.logs.codex.archivedSessions.appending(path: "session.jsonl")
        try write(contents, to: archived)
        let copied = await service.refresh(at: now).snapshot
        XCTAssertEqual(copied.codex.today.processedTokens, 120)

        try write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.refresh(at: now).snapshot
        XCTAssertEqual(replaced.codex.today.processedTokens, 50)
    }

    func testUnknownModelIsIgnoredCompletely() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.snapshot.codex.month, .zero)
        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1])
        XCTAssertEqual(report.ingestion.events, [:])
        XCTAssertEqual(report.ingestion.unpricedModels, ["unknown-model"])
    }

    func testUnpricedModelsOutsideTheHistoryWindowAreNotReported() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(
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

        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1])
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
        try write(contents, to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testColdScanUsesEventTimestampsInsteadOfFileModificationDate() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testColdScanRetainsComparisonPeriodsAndDiscardsOlderHistory() async throws {
        try write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-day",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-day.jsonl")
        )
        try write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-month",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-month.jsonl")
        )
        for index in 1...3 {
            try write(
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

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = root.appending(path: "target.log")
        try write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: locations.logs.codex.sessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.month, .zero)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testClaudePartialsAndCopiesWithoutStableIDsAreIgnored() async throws {
        let partial = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let copy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2, requestID: nil), to: partial)
        try write(claudeLog(output: 40, requestID: nil), to: copy)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.claude.month, .zero)
    }

    private func write(_ text: String, to url: URL) throws {
        try workspace.write(text, to: url, modificationDate: now)
    }

    private func append(_ text: String, to url: URL) throws {
        try workspace.append(text, to: url, modificationDate: now)
    }
}
