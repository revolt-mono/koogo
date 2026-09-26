import Foundation
import XCTest

@testable import Koogo

final class UsageIngestionTests: UsageWorkspaceTestCase {
    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        _ = await service.refresh(at: now).snapshot

        let appended = codexTokenCount(
            last: codexUsage(input: 50, output: 10),
            total: codexUsage(input: 150, output: 30),
            at: "2026-08-25T13:00:00.000Z"
        )
        try workspace.append(appended, to: log)
        let beforeNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(beforeNewline.providers[.codex]?.today.processedTokens, 120)

        try workspace.append("\n", to: log)
        let afterNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(afterNewline.providers[.codex]?.today.processedTokens, 180)
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = workspace.codexSessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try workspace.write(contents, to: active)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        _ = await service.refresh(at: now).snapshot

        let archived = workspace.codexArchivedSessions.appending(path: "session.jsonl")
        try workspace.write(contents, to: archived)
        let copied = await service.refresh(at: now).snapshot
        XCTAssertEqual(copied.providers[.codex]?.today.processedTokens, 120)

        try workspace.write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.refresh(at: now).snapshot
        XCTAssertEqual(replaced.providers[.codex]?.today.processedTokens, 50)
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
        // A fork replays its parent's turn under its own thread, stamped when the fork starts, then runs its own turn.
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

        let snapshot = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 50)
        XCTAssertEqual(snapshot.providers[.codex]?.month.processedTokens, 170)
    }

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = workspace.root.appending(path: "target.log")
        try workspace.write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: workspace.codexSessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.month, UsagePeriodSnapshot())
    }

    func testSymlinkedLogRootIsWalked() async throws {
        let target = workspace.root.appending(path: "sessions-target", directoryHint: .isDirectory)
        try workspace.write(codexLog(input: 100, output: 20), to: target.appending(path: "session.jsonl"))
        try FileManager.default.removeItem(at: workspace.codexSessions)
        try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: target)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(report.snapshot.providers[.codex]?.today.processedTokens, 120)
        let root = report.ingestion.logRoots.first { $0.path == workspace.codexSessions.path }
        XCTAssertEqual(root?.exists, true)
    }

    func testAppearingLogRootRefreshesTheReport() async throws {
        let archived = workspace.codexArchivedSessions
        try FileManager.default.removeItem(at: archived)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let missing = await service.refresh(at: now)
        XCTAssertEqual(missing.ingestion.logRoots.first { $0.path == archived.path }?.exists, false)

        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let appeared = await service.refresh(at: now)

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
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 0)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try workspace.write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.today.processedTokens, 120)
    }

    func testShrunkFileIsRereadAndDeletedFileDropsItsEvents() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        _ = await service.refresh(at: now).snapshot

        try workspace.write(codexLog(input: 40, output: 10, thread: "t"), to: log)
        let shrunk = await service.refresh(at: now).snapshot
        XCTAssertEqual(shrunk.providers[.codex]?.today.processedTokens, 50)

        try FileManager.default.removeItem(at: log)
        let deleted = await service.refresh(at: now).snapshot
        XCTAssertEqual(deleted.providers[.codex]?.today, UsagePeriodSnapshot())
    }

    func testSameSizeRewriteWithNewModificationDateIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        _ = await service.refresh(at: now).snapshot

        try workspace.write(
            codexLog(input: 300, output: 40),
            to: log,
            modificationDate: now.addingTimeInterval(1)
        )
        let rewritten = await service.refresh(at: now).snapshot

        XCTAssertEqual(rewritten.providers[.codex]?.today.processedTokens, 340)
    }

    func testInPlaceRewriteBeforeParsedOffsetIsReread() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        _ = await service.refresh(at: now)

        // Same inode and a larger size, so only the bytes before the parsed offset reveal the rewrite.
        let handle = try FileHandle(forUpdating: log)
        try handle.write(contentsOf: Data(codexLog(input: 300, output: 40, thread: "rewritten").utf8))
        try handle.close()
        let rewritten = await service.refresh(at: now).snapshot

        XCTAssertEqual(rewritten.providers[.codex]?.today.processedTokens, 340)
    }

    func testFileLastWrittenBeforeHistoryWindowIsSkippedUntilAppended() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let skipped = await service.refresh(at: now)
        XCTAssertEqual(skipped.ingestion.trackedFiles[.codex], 0)
        XCTAssertEqual(skipped.snapshot.providers[.codex]?.today, UsagePeriodSnapshot())

        try workspace.append(
            codexTokenCount(
                last: codexUsage(input: 50, output: 10),
                total: codexUsage(input: 150, output: 30),
                at: "2026-08-25T13:00:00.000Z"
            ) + "\n",
            to: log
        )
        let appended = await service.refresh(at: now)
        XCTAssertEqual(appended.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(appended.snapshot.providers[.codex]?.today.processedTokens, 180)
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
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, [])
    }

    func testHistoryWindowMovingForwardDiscardsOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-07-25T17:00:00.000Z")
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let august = await service.refresh(at: now)
        XCTAssertEqual(august.ingestion.events[.codex], 2)

        let nextMonth = try XCTUnwrap(usageTestCalendar.date(byAdding: .month, value: 1, to: now))
        let september = await service.refresh(at: nextMonth)

        XCTAssertEqual(september.ingestion.events[.codex], 1)
        XCTAssertEqual(september.snapshot.providers[.codex]?.month, UsagePeriodSnapshot())
        XCTAssertEqual(september.snapshot.summary.month.costChange, .decrease(fraction: 1))
    }

    func testHistoryWindowMovingBackwardRescansOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-06-25T17:00:00.000Z")
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let august = await service.refresh(at: now)
        XCTAssertEqual(august.ingestion.events[.codex], 1)

        let july = try XCTUnwrap(usageTestCalendar.date(byAdding: .month, value: -1, to: now))
        let rescanned = await service.refresh(at: july)

        XCTAssertEqual(rescanned.ingestion.events[.codex], 2)
        XCTAssertEqual(rescanned.snapshot.providers[.codex]?.month, UsagePeriodSnapshot())
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
