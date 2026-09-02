import Foundation
import XCTest

@testable import Koogo

final class UsageIngestionTests: UsageWorkspaceTestCase {
    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        let appended = codexToken(
            timestamp: "2026-08-25T13:00:00.000Z",
            lastInput: 50,
            lastOutput: 10,
            totalInput: 150,
            totalOutput: 30
        )
        try workspace.append(appended, to: log)
        let beforeNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(beforeNewline.codex.today.processedTokens, 120)

        try workspace.append("\n", to: log)
        let afterNewline = await service.refresh(at: now).snapshot
        XCTAssertEqual(afterNewline.codex.today.processedTokens, 180)
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try workspace.write(contents, to: active)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        let archived = locations.logs.codex.archivedSessions.appending(path: "session.jsonl")
        try workspace.write(contents, to: archived)
        let copied = await service.refresh(at: now).snapshot
        XCTAssertEqual(copied.codex.today.processedTokens, 120)

        try workspace.write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.refresh(at: now).snapshot
        XCTAssertEqual(replaced.codex.today.processedTokens, 50)
    }

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = workspace.root.appending(path: "target.log")
        try workspace.write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: locations.logs.codex.sessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.month, UsagePeriodSnapshot())
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try workspace.write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testShrunkFileIsRereadAndDeletedFileDropsItsEvents() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        try workspace.write(codexLog(input: 40, output: 10, thread: "t"), to: log)
        let shrunk = await service.refresh(at: now).snapshot
        XCTAssertEqual(shrunk.codex.today.processedTokens, 50)

        try FileManager.default.removeItem(at: log)
        let deleted = await service.refresh(at: now).snapshot
        XCTAssertEqual(deleted.codex.today, UsagePeriodSnapshot())
    }

    func testSameSizeRewriteWithNewModificationDateIsReread() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now).snapshot

        try workspace.write(
            codexLog(input: 300, output: 40),
            to: log,
            modificationDate: now.addingTimeInterval(1)
        )
        let rewritten = await service.refresh(at: now).snapshot

        XCTAssertEqual(rewritten.codex.today.processedTokens, 340)
    }

    func testHistoryWindowMovingForwardDiscardsOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-07-25T17:00:00.000Z")
        let service = UsageService(locations: locations, calendar: calendar)
        let august = await service.refresh(at: now)
        XCTAssertEqual(august.ingestion.events[.codex], 2)

        let nextMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: now))
        let september = await service.refresh(at: nextMonth)

        XCTAssertEqual(september.ingestion.events[.codex], 1)
        XCTAssertEqual(september.snapshot.codex.month, UsagePeriodSnapshot())
        XCTAssertEqual(september.snapshot.summary.month.costChange, .decrease(fraction: 1))
    }

    func testHistoryWindowMovingBackwardRescansOlderEvents() async throws {
        try writeAugustLog(andOlderLogAt: "2026-06-25T17:00:00.000Z")
        let service = UsageService(locations: locations, calendar: calendar)
        let august = await service.refresh(at: now)
        XCTAssertEqual(august.ingestion.events[.codex], 1)

        let july = try XCTUnwrap(calendar.date(byAdding: .month, value: -1, to: now))
        let rescanned = await service.refresh(at: july)

        XCTAssertEqual(rescanned.ingestion.events[.codex], 2)
        XCTAssertEqual(rescanned.snapshot.codex.month, UsagePeriodSnapshot())
    }

    private func writeAugustLog(andOlderLogAt olderTimestamp: String) throws {
        try workspace.write(
            codexLog(input: 100, output: 20, thread: "august"),
            to: locations.logs.codex.sessions.appending(path: "august.jsonl")
        )
        try workspace.write(
            codexLog(input: 200, output: 40, thread: "older", usageTimestamp: olderTimestamp),
            to: locations.logs.codex.sessions.appending(path: "older.jsonl")
        )
    }
}
