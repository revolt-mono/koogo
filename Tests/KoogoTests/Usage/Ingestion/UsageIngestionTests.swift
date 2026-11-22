import Foundation
import Testing

@testable import Koogo

struct UsageIngestionTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `refresh reads only complete appended lines`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    let appended = CodexLog.tokenUsageRecord(
      CodexLog.usage(input: 50, output: 10),
      response: "second",
      at: "2026-08-25T13:00:00.000Z",
    )
    try workspace.append(appended, to: log)
    try workspace.write(
      CodexLog.session(input: 1, output: 0, response: "witness"),
      to: workspace.codexSessions.appending(path: "witness.jsonl"),
    )
    let beforeNewline = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] == 2 }
    #expect(beforeNewline.snapshot.todayTokens(.codex) == 121)

    try workspace.append("\n", to: log)
    let afterNewline = try await workspace.refresh(pipeline) { $0.snapshot.todayTokens(.codex) != 121 }
    #expect(afterNewline.snapshot.todayTokens(.codex) == 181)
  }

  @Test
  func `refresh counts lines appended through an open handle`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    let writer = try workspace.openWriter(to: log)
    defer { try? writer.close() }
    let second = CodexLog.tokenUsageRecord(
      CodexLog.usage(input: 50, output: 10),
      response: "second",
    )
    try writer.write(contentsOf: Data((second + "\n").utf8))
    let appended = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(appended.snapshot.todayTokens(.codex) == 180)

    let third = CodexLog.tokenUsageRecord(CodexLog.usage(input: 20, output: 5), response: "third")
    try writer.write(contentsOf: Data(third.prefix(third.count / 2).utf8))
    let partial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(partial.snapshot.todayTokens(.codex) == 180)

    try writer.write(contentsOf: Data((third.dropFirst(third.count / 2) + "\n").utf8))
    let completed = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(completed.snapshot.todayTokens(.codex) == 205)
  }

  @Test
  func `refresh follows logs resumed through an open handle after leaving the window`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: log,
      modificationDate: UsageFixture.timestamp.addingTimeInterval(-40 * 86_400),
    )
    let pipeline = workspace.makePipeline()
    let dormant = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(dormant.ingestion.trackedFiles[.codex] == 0)

    let writer = try workspace.openWriter(to: log)
    defer { try? writer.close() }
    let second = CodexLog.tokenUsageRecord(
      CodexLog.usage(input: 50, output: 10),
      response: "second",
    )
    try writer.write(contentsOf: Data((second + "\n").utf8))
    let resumed = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(resumed.ingestion.trackedFiles[.codex] == 1)
    #expect(resumed.snapshot.todayTokens(.codex) == 180)
  }

  @Test
  func `archive copy does not double count and replacement drops removed events`() async throws {
    let active = workspace.codexSessions.appending(path: "session.jsonl")
    let contents = CodexLog.session(input: 100, output: 20)
    try workspace.write(contents, to: active)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    let archived = workspace.codexArchivedSessions.appending(path: "session.jsonl")
    try workspace.write(contents, to: archived)
    let copied = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] == 2 }
    #expect(copied.snapshot.todayTokens(.codex) == 120)

    try workspace.write(CodexLog.session(input: 40, output: 10, response: "replacement"), to: active)
    try FileManager.default.removeItem(at: archived)
    let replaced = try await workspace.refresh(pipeline) {
      $0.ingestion.trackedFiles[.codex] == 1 && $0.snapshot.todayTokens(.codex) != 120
    }
    #expect(replaced.snapshot.todayTokens(.codex) == 50)
  }

  @Test
  func `codex fork replay counts once at the parent time`() async throws {
    let parentRequest = CodexLog.usage(input: 100, output: 20)
    try workspace.write(
      [
        CodexLog.meta(),
        CodexLog.turn(),
        CodexLog.tokenUsageRecord(parentRequest, at: "2026-08-24T12:00:00.000Z"),
        "",
      ].joined(separator: "\n"),
      to: workspace.codexSessions.appending(path: "parent.jsonl"),
    )
    try workspace.write(
      [
        CodexLog.meta(),
        CodexLog.turn(),
        CodexLog.tokenUsageRecord(parentRequest, at: "2026-08-25T12:00:00.000Z"),
        CodexLog.tokenUsageRecord(
          CodexLog.usage(input: 40, output: 10),
          response: "fork",
          at: "2026-08-25T12:00:00.000Z",
        ),
        "",
      ].joined(separator: "\n"),
      to: workspace.codexSessions.appending(path: "fork.jsonl"),
    )

    let snapshot = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.todayTokens(.codex) == 50)
    #expect(snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens == 170)
  }

  @Test
  func `cold scan parses lines across read chunks`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    let ignored =
      "{\"type\":\"ignored\",\"padding\":\""
        + String(repeating: "x", count: 4_194_304)
        + "\"}\n"
    try workspace.write(ignored + CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()

    let snapshot = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.todayTokens(.codex) == 120)
  }

  @Test
  func `same size rewrite with new modification date is reread`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    try workspace.write(
      CodexLog.session(input: 300, output: 40),
      to: log,
      modificationDate: UsageFixture.timestamp.addingTimeInterval(1),
    )
    let rewritten = try await workspace.refresh(pipeline) { $0.snapshot.todayTokens(.codex) != 120 }

    #expect(rewritten.snapshot.todayTokens(.codex) == 340)
  }

  @Test
  func `in place rewrite before parsed offset is reread`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    let handle = try FileHandle(forUpdating: log)
    try handle.write(contentsOf: Data(CodexLog.session(input: 300, output: 40, response: "rewritten").utf8))
    try handle.close()
    let rewritten = try await workspace.refresh(pipeline) { $0.snapshot.todayTokens(.codex) != 120 }

    #expect(rewritten.snapshot.todayTokens(.codex) == 340)
  }

  @Test
  func `file last written before history window is skipped until appended`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 0)],
      ofItemAtPath: log.path,
    )
    let pipeline = workspace.makePipeline()

    let skipped = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(skipped.ingestion.trackedFiles[.codex] == 0)
    #expect(skipped.snapshot.providers[.codex]?.periods[.today].total == UsagePeriodSnapshot())

    try workspace.append(
      CodexLog.tokenUsageRecord(
        CodexLog.usage(input: 50, output: 10),
        response: "second",
        at: "2026-08-25T13:00:00.000Z",
      ) + "\n",
      to: log,
    )
    let appended = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] == 1 }
    #expect(appended.snapshot.todayTokens(.codex) == 180)
  }

  @Test
  func `unpriced models outside the history window are not reported`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(
      CodexLog.session(
        input: 100,
        output: 20,
        model: "unknown-model",
        usageTimestamp: "2026-05-01T12:00:00.000Z",
      ),
      to: log,
    )
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.trackedFiles == [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
    #expect(report.ingestion.unpricedModels == [])
  }

  @Test
  func `report counts malformed records but not other record kinds`() async throws {
    let request = CodexLog.usage(input: 100, output: 20)
    try workspace.write(
      [
        CodexLog.meta(),
        CodexLog.turn(),
        CodexLog.tokenUsageRecord(request)
          .replacing(#""usage":\#(request),"#, with: ""),
        CodexLog.tokenUsageRecord(request),
        "",
      ].joined(separator: "\n"),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    let progress = #"{"type":"progress","data":{"message":{"type":"assistant","message":{"usage":{}}}}}"#
    try workspace.write(
      progress + "\n" + ClaudeLog.session(output: 40),
      to: workspace.claudeProjects.appending(path: "project/session.jsonl"),
    )

    let report = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.malformedLines == [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
    #expect(report.snapshot.todayTokens(.codex) == 120)
    #expect(report.snapshot.todayTokens(.claude) == 50)
  }

  @Test
  func `history window moving backward rescans older events`() async throws {
    try workspace.write(
      CodexLog.session(input: 100, output: 20, response: "august"),
      to: workspace.codexSessions.appending(path: "august.jsonl"),
    )
    try workspace.write(
      CodexLog.session(input: 200, output: 40, response: "older", usageTimestamp: "2026-07-26T23:59:59.999Z"),
      to: workspace.codexSessions.appending(path: "older.jsonl"),
    )
    let pipeline = workspace.makePipeline()
    let august = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(august.ingestion.events[.codex] == 1)

    let previousDay = try Date("2026-08-24T23:59:59.999Z", strategy: .iso8601)
    let rescanned = await pipeline.run(at: previousDay, providers: Provider.allCases)

    #expect(rescanned.ingestion.events[.codex] == 2)
    #expect(rescanned.snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens == 240)
  }

  private let workspace: UsageTestWorkspace
}
