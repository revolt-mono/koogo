import Foundation
import Testing

@testable import Koogo

struct LogFileTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `append that cannot be read is read once it can be`() throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    var parsed = try #require(
      ParsedLog<CodexUsageLogParser>(
        AppendOnlyFile(log.path, observed: metadata(of: log)),
        since: UsageTimestamp(.distantPast),
      )
    )
    try workspace.append(
      CodexLog.tokenUsageRecord(
        CodexLog.usage(input: 50, output: 10),
        response: "second",
        at: "2026-08-25T13:00:00.000Z",
      ) + "\n",
      to: log,
    )

    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: log.path)
    parsed.sync(observed: try metadata(of: log), since: UsageTimestamp(.distantPast))
    #expect(parsed.events.count == 1)

    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: log.path)
    parsed.sync(observed: try metadata(of: log), since: UsageTimestamp(.distantPast))
    #expect(parsed.events.count == 2)
  }

  @Test
  func `compressed rollouts are read like plain logs`() async throws {
    try workspace.write(CodexLog.compressedSession, to: workspace.codexSessions.appending(path: "session.jsonl.zst"))
    try workspace.write(
      Data("not a zstd frame".utf8),
      to: workspace.codexArchivedSessions.appending(path: "broken.jsonl.zst"),
    )

    let report = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.trackedFiles[.codex] == 2)
    #expect(report.ingestion.events[.codex] == 1)
    #expect(report.snapshot.todayTokens(.codex) == 120)
  }

  @Test
  func `compression replacing a plain rollout keeps its events once`() async throws {
    let plain = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: plain)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    try workspace.write(CodexLog.compressedSession, to: workspace.codexSessions.appending(path: "session.jsonl.zst"))
    let both = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] == 2 }
    #expect(both.snapshot.todayTokens(.codex) == 120)

    try FileManager.default.removeItem(at: plain)
    let compressed = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] == 1 }
    #expect(compressed.snapshot.todayTokens(.codex) == 120)
  }

  @Test
  func `lines spanning decoded chunks are delivered whole`() throws {
    let padding = String(repeating: "x", count: 1 << 20)
    let text = "{\"type\":\"ignored\",\"padding\":\"\(padding)\"}\n" + CodexLog.session(input: 100, output: 20)
    let url = workspace.codexSessions.appending(path: "padded.jsonl.zst")
    try workspace.write(Data.zstdFrame(of: text), to: url)

    let log = try #require(
      ParsedLog<CodexUsageLogParser>(
        CompressedFile(url.path, observed: metadata(of: url)),
        since: UsageTimestamp(.distantPast),
      )
    )

    #expect(log.events.count == 1)
    #expect(log.droppedInput.malformedLines == 0)
  }

  private let workspace: UsageTestWorkspace

  private func metadata(of url: URL) throws -> UsageFileMetadata {
    try #require(UsageFileMetadata(path: url.path))
  }
}

extension Data {
  /// a frame of stored blocks with a 1 MiB window needs no compressor; each block holds at most 128 KiB.
  static func zstdFrame(of text: String) -> Data {
    var frame = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x50])
    let bytes = Array(text.utf8)
    var offset = 0
    repeat {
      let block = bytes[offset...].prefix(1 << 17)
      let header = UInt32(block.count) << 3 | (block.endIndex == bytes.count ? 1 : 0)
      frame.append(contentsOf: [UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16 & 0xFF)])
      frame.append(contentsOf: block)
      offset = block.endIndex
    } while offset < bytes.count
    return frame
  }
}
