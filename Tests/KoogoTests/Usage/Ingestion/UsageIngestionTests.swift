import Foundation
import XCTest

@testable import Koogo

final class UsageIngestionTests: UsageWorkspaceTestCase {
    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        let appended = codexTokenCount(
            last: codexUsage(input: 50, output: 10),
            total: codexUsage(input: 150, output: 30),
            at: "2026-08-25T13:00:00.000Z"
        )
        try workspace.append(appended, to: log)
        // A session written after the partial line shows that the walk has passed over it.
        try workspace.write(
            codexLog(input: 1, output: 0, thread: "witness"),
            to: workspace.codexSessions.appending(path: "witness.jsonl")
        )
        let beforeNewline = try await refresh(service) { $0.ingestion.trackedFiles[.codex] == 2 }
        XCTAssertEqual(beforeNewline.snapshot.todayTokens(.codex), 121)

        try workspace.append("\n", to: log)
        let afterNewline = try await refresh(service) { $0.snapshot.todayTokens(.codex) != 121 }
        XCTAssertEqual(afterNewline.snapshot.todayTokens(.codex), 181)
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = workspace.codexSessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try workspace.write(contents, to: active)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        let archived = workspace.codexArchivedSessions.appending(path: "session.jsonl")
        try workspace.write(contents, to: archived)
        let copied = try await refresh(service) { $0.ingestion.trackedFiles[.codex] == 2 }
        XCTAssertEqual(copied.snapshot.todayTokens(.codex), 120)

        try workspace.write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = try await refresh(service) {
            $0.ingestion.trackedFiles[.codex] == 1 && $0.snapshot.todayTokens(.codex) != 120
        }
        XCTAssertEqual(replaced.snapshot.todayTokens(.codex), 50)
    }

    func testCodexForkReplayCountsOnceAtTheParentTime() async throws {
        let parentRequest = codexUsage(input: 100, output: 20)
        try workspace.write(
            [
                codexMeta(thread: "parent"),
                codexTurn(),
                codexTokenCount(last: parentRequest, total: parentRequest, at: "2026-08-24T12:00:00.000Z"),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "parent.jsonl")
        )
        try workspace.write(
            [
                codexMeta(thread: "fork"),
                codexTurn(),
                codexTokenCount(last: parentRequest, total: parentRequest, at: "2026-08-25T12:00:00.000Z"),
                codexTurn(id: "fork-turn"),
                codexTokenCount(
                    last: codexUsage(input: 40, output: 10),
                    total: codexUsage(input: 140, output: 30),
                    at: "2026-08-25T12:00:00.000Z"
                ),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "fork.jsonl")
        )

        let snapshot = await makePipeline().run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.todayTokens(.codex), 50)
        XCTAssertEqual(snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens, 170)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try workspace.write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()

        let snapshot = await service.run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.todayTokens(.codex), 120)
    }

    func testSameSizeRewriteWithNewModificationDateIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        try workspace.write(
            codexLog(input: 300, output: 40),
            to: log,
            modificationDate: usageTestTimestamp.addingTimeInterval(1)
        )
        let rewritten = try await refresh(service) { $0.snapshot.todayTokens(.codex) != 120 }

        XCTAssertEqual(rewritten.snapshot.todayTokens(.codex), 340)
    }

    func testInPlaceRewriteBeforeParsedOffsetIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        let handle = try FileHandle(forUpdating: log)
        try handle.write(contentsOf: Data(codexLog(input: 300, output: 40, thread: "rewritten").utf8))
        try handle.close()
        let rewritten = try await refresh(service) { $0.snapshot.todayTokens(.codex) != 120 }

        XCTAssertEqual(rewritten.snapshot.todayTokens(.codex), 340)
    }

    func testFileLastWrittenBeforeHistoryWindowIsSkippedUntilAppended() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = makePipeline()

        let skipped = await service.run(at: usageTestTimestamp, providers: Provider.allCases)
        XCTAssertEqual(skipped.ingestion.trackedFiles[.codex], 0)
        XCTAssertEqual(skipped.snapshot.providers[.codex]?.periods[.today].total, UsagePeriodSnapshot())

        try workspace.append(
            codexTokenCount(
                last: codexUsage(input: 50, output: 10),
                total: codexUsage(input: 150, output: 30),
                at: "2026-08-25T13:00:00.000Z"
            ) + "\n",
            to: log
        )
        let appended = try await refresh(service) { $0.ingestion.trackedFiles[.codex] == 1 }
        XCTAssertEqual(appended.snapshot.todayTokens(.codex), 180)
    }

    func testUnpricedModelsOutsideTheHistoryWindowAreNotReported() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(
            codexLog(
                input: 100,
                output: 20,
                model: "unknown-model",
                usageTimestamp: "2026-05-01T12:00:00.000Z"
            ),
            to: log
        )
        let service = makePipeline()

        let report = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, [])
    }

    func testReportCountsMalformedRecordsButNotOtherRecordKinds() async throws {
        let request = codexUsage(input: 100, output: 20)
        try workspace.write(
            [
                codexMeta(),
                codexTurn(),
                codexTokenCount(last: request, total: request)
                    .replacingOccurrences(of: #""last_token_usage":\#(request),"#, with: ""),
                codexTokenCount(last: request, total: request),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        let progress = #"{"type":"progress","data":{"message":{"type":"assistant","message":{"usage":{}}}}}"#
        try workspace.write(
            progress + "\n" + claudeLog(output: 40),
            to: workspace.claudeProjects.appending(path: "project/session.jsonl")
        )

        let report = await makePipeline().run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.malformedLines, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.snapshot.todayTokens(.codex), 120)
        XCTAssertEqual(report.snapshot.todayTokens(.claude), 50)
    }

    func testHistoryWindowMovingBackwardRescansOlderEvents() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20, thread: "august"),
            to: workspace.codexSessions.appending(path: "august.jsonl")
        )
        try workspace.write(
            codexLog(input: 200, output: 40, thread: "older", usageTimestamp: "2026-07-26T23:59:59.999Z"),
            to: workspace.codexSessions.appending(path: "older.jsonl")
        )
        let service = makePipeline()
        let august = await service.run(at: usageTestTimestamp, providers: Provider.allCases)
        XCTAssertEqual(august.ingestion.events[.codex], 1)

        let previousDay = try XCTUnwrap(Date(iso8601: "2026-08-24T23:59:59.999Z"))
        let rescanned = await service.run(at: previousDay, providers: Provider.allCases)

        XCTAssertEqual(rescanned.ingestion.events[.codex], 2)
        XCTAssertEqual(rescanned.snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens, 240)
    }
}
