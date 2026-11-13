import XCTest

@testable import Koogo

final class LogStoreMemoryTests: UsageWorkspaceTestCase {
  func testVisitingEventsDoesNotCopyTheStore() throws {
    try MemoryMeasurement.skipUnlessRequested()
    let usage = CodexLog.usage(input: 100, output: 20)
    let turns = (1...20_000).map {
      CodexLog.turn() + "\n" + CodexLog.tokenUsageRecord(usage, response: "response-\($0)") + "\n"
    }
    try workspace.write(turns.joined(), to: workspace.codexSessions.appending(path: "session.jsonl"))
    var store = LogStore()
    store.sync(
      roots: Provider.codex.logRoots(under: workspace.root),
      since: UsageFixture.timestamp.addingTimeInterval(-86_400),
    )

    let before = MemoryMeasurement.allocatedHeapBytes()
    var peak = before
    var visited = 0
    let stats = store.collect { _ in
      visited += 1
      if visited.isMultiple(of: 1_000) {
        peak = max(peak, MemoryMeasurement.allocatedHeapBytes())
      }
    }

    XCTAssertEqual(visited, 20_000)
    XCTAssertEqual(stats.events[.codex], 20_000)
    XCTAssertLessThan(peak - before, 2 * 1_024 * 1_024)
  }

  func testDecodingACompressedLogKeepsItsWindowOutOfTheHeap() throws {
    try MemoryMeasurement.skipUnlessRequested()
    let url = workspace.codexSessions.appending(path: "session.jsonl.zst")
    try workspace.write(Data.zstdFrame(of: CodexLog.session(input: 100, output: 20)), to: url)
    var file = CompressedFile(url.path, observed: try XCTUnwrap(UsageFileMetadata(path: url.path)))

    let before = MemoryMeasurement.allocatedHeapBytes()
    var peak = before
    var lines = 0
    _ = file.read(
      restart: { },
      consume: { _ in
        lines += 1
        peak = max(peak, MemoryMeasurement.allocatedHeapBytes())
      },
    )

    XCTAssertGreaterThan(lines, 0)
    XCTAssertLessThan(peak - before, 256 * 1_024)
  }

  func testTrackedEventsRetainCompactRecords() throws {
    try MemoryMeasurement.skipUnlessRequested()
    let fileCount = 400
    let repliesPerFile = 125
    for file in 0..<fileCount {
      let replies = (0..<repliesPerFile).map { reply in
        let serial = String(format: "%08d%04d", file, reply)
        return """
          {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"req_011CVbXq7\(serial)","effort":"high","message":{"id":"msg_01Hx9QmV3\(serial)","model":"claude-mythos-5-1","usage":{"input_tokens":10,"output_tokens":20}}}
          """
      }
      try workspace.write(
        replies.joined(separator: "\n") + "\n",
        to: workspace.claudeProjects.appending(path: "project/session-\(file).jsonl"),
      )
    }
    let roots = Provider.claude.logRoots(under: workspace.root)

    let before = MemoryMeasurement.allocatedHeapBytes()
    var store = LogStore()
    store.sync(roots: roots, since: UsageFixture.timestamp.addingTimeInterval(-86_400))
    let retainedPerEvent = (MemoryMeasurement.allocatedHeapBytes() - before) / (fileCount * repliesPerFile)

    XCTAssertEqual(store.collect { _ in }.events[.claude], fileCount * repliesPerFile)
    XCTAssertLessThan(retainedPerEvent, 110)
  }
}
