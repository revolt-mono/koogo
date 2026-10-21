import Foundation
import XCTest

@testable import Koogo

final class LogFileTests: UsageWorkspaceTestCase {
    func testAppendThatCannotBeReadReportsNoChangeUntilItCanBe() throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: log)
        var parsed = try XCTUnwrap(
            ParsedLog<CodexUsageLogParser>(
                AppendOnlyFile(log.path, observed: try metadata(of: log)),
                since: .distantPast
            )
        )
        try workspace.append(
            codexTokenUsageRecord(
                codexUsage(input: 50, output: 10),
                thread: codexUsage(input: 150, output: 30),
                at: "2026-08-25T13:00:00.000Z"
            ) + "\n",
            to: log
        )

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: log.path)
        XCTAssertFalse(parsed.sync(observed: try metadata(of: log)))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: log.path)
        XCTAssertTrue(parsed.sync(observed: try metadata(of: log)))
        XCTAssertEqual(parsed.events.count, 2)
    }

    func testCompressedRolloutsAreReadLikePlainLogs() async throws {
        try workspace.write(codexCompressedLog, to: workspace.codexSessions.appending(path: "session.jsonl.zst"))
        try workspace.write(
            Data("not a zstd frame".utf8),
            to: workspace.codexArchivedSessions.appending(path: "broken.jsonl.zst")
        )

        let report = await makePipeline().run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 2)
        XCTAssertEqual(report.ingestion.events[.codex], 1)
        XCTAssertEqual(report.snapshot.todayTokens(.codex), 120)
    }

    func testCompressionReplacingAPlainRolloutKeepsItsEventsOnce() async throws {
        let plain = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20), to: plain)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        try workspace.write(codexCompressedLog, to: workspace.codexSessions.appending(path: "session.jsonl.zst"))
        let both = try await refresh(service) { $0.ingestion.trackedFiles[.codex] == 2 }
        XCTAssertEqual(both.snapshot.todayTokens(.codex), 120)

        try FileManager.default.removeItem(at: plain)
        let compressed = try await refresh(service) { $0.ingestion.trackedFiles[.codex] == 1 }
        XCTAssertEqual(compressed.snapshot.todayTokens(.codex), 120)
    }

    func testLinesSpanningDecodedChunksAreDeliveredWhole() throws {
        let padding = String(repeating: "x", count: 1 << 20)
        let text = "{\"type\":\"ignored\",\"padding\":\"\(padding)\"}\n" + codexLog(input: 100, output: 20)
        let url = workspace.codexSessions.appending(path: "padded.jsonl.zst")
        try workspace.write(zstdFrame(of: text), to: url)

        let log = try XCTUnwrap(
            ParsedLog<CodexUsageLogParser>(
                CompressedFile(url.path, observed: try metadata(of: url)),
                since: .distantPast
            )
        )

        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.tally.malformedLines, 0)
    }

    private func metadata(of url: URL) throws -> UsageFileMetadata {
        try XCTUnwrap(UsageFileMetadata(path: url.path))
    }
}

/// a frame of stored blocks with a 1 MiB window needs no compressor; each block holds at most 128 KiB.
private func zstdFrame(of text: String) -> Data {
    var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x50])
    let bytes = Array(text.utf8)
    var offset = 0
    repeat {
        let block = bytes[offset..<min(offset + (1 << 17), bytes.count)]
        let header = UInt32(block.count) << 3 | (block.endIndex == bytes.count ? 1 : 0)
        frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16 & 0xFF)])
        frame.append(contentsOf: block)
        offset = block.endIndex
    } while offset < bytes.count
    return frame
}
