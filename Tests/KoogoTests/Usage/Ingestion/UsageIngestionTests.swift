import Foundation
import XCTest

@testable import Koogo

final class UsageIngestionTests: UsageWorkspaceTestCase {
    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: now, providers: Provider.allCases).snapshot

        let appended = codexTokenCount(
            last: codexUsage(input: 50, output: 10),
            total: codexUsage(input: 150, output: 30),
            at: "2026-08-25T13:00:00.000Z"
        )
        try workspace.append(appended, to: log)
        let beforeNewline = await service.run(at: now, providers: Provider.allCases).snapshot
        XCTAssertEqual(beforeNewline.providers[.codex]?.periods[.today].total.processedTokens, 120)

        try workspace.append("\n", to: log)
        let afterNewline = await service.run(at: now, providers: Provider.allCases).snapshot
        XCTAssertEqual(afterNewline.providers[.codex]?.periods[.today].total.processedTokens, 180)
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = workspace.codexSessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try workspace.write(contents, to: active)
        let service = makePipeline()
        _ = await service.run(at: now, providers: Provider.allCases).snapshot

        let archived = workspace.codexArchivedSessions.appending(path: "session.jsonl")
        try workspace.write(contents, to: archived)
        let copied = await service.run(at: now, providers: Provider.allCases).snapshot
        XCTAssertEqual(copied.providers[.codex]?.periods[.today].total.processedTokens, 120)

        try workspace.write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.run(at: now, providers: Provider.allCases).snapshot
        XCTAssertEqual(replaced.providers[.codex]?.periods[.today].total.processedTokens, 50)
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

        let snapshot = await makePipeline().run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.periods[.today].total.processedTokens, 50)
        XCTAssertEqual(snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens, 170)
    }

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = workspace.root.appending(path: "target.log")
        try workspace.write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: workspace.codexSessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = makePipeline()

        let snapshot = await service.run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.periods[.last30Days].total, UsagePeriodSnapshot())
    }

    func testSymlinkedLogRootIsWalked() async throws {
        let target = workspace.root.appending(path: "sessions-target", directoryHint: .isDirectory)
        try workspace.write(codexLog(input: 100, output: 20), to: target.appending(path: "session.jsonl"))
        try FileManager.default.removeItem(at: workspace.codexSessions)
        try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: target)
        let service = makePipeline()

        let report = await service.run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(report.snapshot.providers[.codex]?.periods[.today].total.processedTokens, 120)
        let root = report.ingestion.logRoots.first { $0.path == workspace.codexSessions.path }
        XCTAssertEqual(root?.exists, true)
    }

    func testAppearingLogRootRefreshesTheReport() async throws {
        let archived = workspace.codexArchivedSessions
        try FileManager.default.removeItem(at: archived)
        let service = makePipeline()
        let missing = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(missing.ingestion.logRoots.first { $0.path == archived.path }?.exists, false)

        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let appeared = await service.run(at: now, providers: Provider.allCases)

        XCTAssertEqual(appeared.ingestion.logRoots.first { $0.path == archived.path }?.exists, true)
    }

    func testHiddenFilesAndDirectoriesAreNotScanned() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20, thread: "cached"),
            to: workspace.codexSessions.appending(path: ".cache/a.jsonl")
        )
        try workspace.write(
            codexLog(input: 100, output: 20, thread: "hidden"),
            to: workspace.codexSessions.appending(path: ".b.jsonl")
        )
        let service = makePipeline()

        let report = await service.run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 0)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try workspace.write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()

        let snapshot = await service.run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.periods[.today].total.processedTokens, 120)
    }

    func testSameSizeRewriteWithNewModificationDateIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: now, providers: Provider.allCases).snapshot

        try workspace.write(
            codexLog(input: 300, output: 40),
            to: log,
            modificationDate: now.addingTimeInterval(1)
        )
        let rewritten = await service.run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(rewritten.providers[.codex]?.periods[.today].total.processedTokens, 340)
    }

    func testInPlaceRewriteBeforeParsedOffsetIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = makePipeline()
        _ = await service.run(at: now, providers: Provider.allCases)

        let handle = try FileHandle(forUpdating: log)
        try handle.write(contentsOf: Data(codexLog(input: 300, output: 40, thread: "rewritten").utf8))
        try handle.close()
        let rewritten = await service.run(at: now, providers: Provider.allCases).snapshot

        XCTAssertEqual(rewritten.providers[.codex]?.periods[.today].total.processedTokens, 340)
    }

    func testFileLastWrittenBeforeHistoryWindowIsSkippedUntilAppended() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = makePipeline()

        let skipped = await service.run(at: now, providers: Provider.allCases)
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
        let appended = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(appended.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(appended.snapshot.providers[.codex]?.periods[.today].total.processedTokens, 180)
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

        let report = await service.run(at: now, providers: Provider.allCases)

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

        let report = await makePipeline().run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.malformedLines, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.snapshot.providers[.codex]?.periods[.today].total.processedTokens, 120)
        XCTAssertEqual(report.snapshot.providers[.claude]?.periods[.today].total.processedTokens, 50)
    }

    func testHistoryWindowMovingForwardDiscardsOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-06-27T00:00:00Z")
        let service = makePipeline()
        let august = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(august.ingestion.events[.codex], 2)

        let nextDay = try XCTUnwrap(Date(iso8601: "2026-08-26T00:00:00Z"))
        let refreshed = await service.run(at: nextDay, providers: Provider.allCases)

        XCTAssertEqual(refreshed.ingestion.events[.codex], 1)
        XCTAssertEqual(refreshed.snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens, 120)
        XCTAssertEqual(refreshed.snapshot.summary.last30Days.costChange, .increase(fraction: 1))
    }

    func testHistoryWindowMovingBackwardRescansOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-06-26T23:59:59.999Z")
        let service = makePipeline()
        let august = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(august.ingestion.events[.codex], 1)

        let previousDay = try XCTUnwrap(Date(iso8601: "2026-08-24T23:59:59.999Z"))
        let rescanned = await service.run(at: previousDay, providers: Provider.allCases)

        XCTAssertEqual(rescanned.ingestion.events[.codex], 2)
        XCTAssertEqual(rescanned.snapshot.providers[.codex]?.periods[.last30Days].total, UsagePeriodSnapshot())
    }

    private func writeAugustLog(andOlderLogAt olderTimestamp: String) throws {
        try workspace.write(
            codexLog(input: 100, output: 20, thread: "august"),
            to: workspace.codexSessions.appending(path: "august.jsonl")
        )
        try workspace.write(
            codexLog(input: 200, output: 40, thread: "older", usageTimestamp: olderTimestamp),
            to: workspace.codexSessions.appending(path: "older.jsonl")
        )
    }
}
