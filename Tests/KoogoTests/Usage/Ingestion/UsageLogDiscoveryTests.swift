import Foundation
import Testing

@testable import Koogo

struct UsageLogDiscoveryTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `cold scan ignores jsonl symlinks`() async throws {
    let target = workspace.root.appending(path: "target.log")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: target)
    try FileManager.default.createSymbolicLink(
      at: workspace.codexSessions.appending(path: "session.jsonl"),
      withDestinationURL: target,
    )
    let pipeline = workspace.makePipeline()

    let snapshot = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.providers[.codex]?.periods[.last30Days].total == UsagePeriodSnapshot())
  }

  @Test
  func `symlinked log root is walked`() async throws {
    let target = workspace.root.appending(path: "sessions-target", directoryHint: .isDirectory)
    try workspace.write(CodexLog.session(input: 100, output: 20), to: target.appending(path: "session.jsonl"))
    try FileManager.default.removeItem(at: workspace.codexSessions)
    try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: target)
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.trackedFiles[.codex] == 1)
    #expect(report.snapshot.todayTokens(.codex) == 120)
    let root = report.ingestion.logRoots.first { $0.path == workspace.codexSessions.path }
    #expect(root?.exists == true)

    try workspace.append(
      CodexLog.tokenUsageRecord(
        CodexLog.usage(input: 50, output: 10),
        response: "second",
      ) + "\n",
      to: target.appending(path: "session.jsonl"),
    )
    let appended = try await workspace.refresh(pipeline) { $0.snapshot.todayTokens(.codex) != 120 }
    #expect(appended.snapshot.todayTokens(.codex) == 180)
  }

  @Test
  func `retargeted log root symlink is walked`() async throws {
    let first = workspace.root.appending(path: "first-target", directoryHint: .isDirectory)
    let second = workspace.root.appending(path: "second-target", directoryHint: .isDirectory)
    try workspace.write(CodexLog.session(input: 100, output: 20), to: first.appending(path: "session.jsonl"))
    try workspace.write(CodexLog.session(input: 40, output: 10), to: second.appending(path: "session.jsonl"))
    try FileManager.default.removeItem(at: workspace.codexSessions)
    try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: first)
    let pipeline = workspace.makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(initial.snapshot.todayTokens(.codex) == 120)

    try FileManager.default.removeItem(at: workspace.codexSessions)
    try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: second)
    let retargeted = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(retargeted.snapshot.todayTokens(.codex) == 50)
  }

  @Test
  func `directories that appear move in or vanish later are followed`() async throws {
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    try workspace.write(
      ClaudeLog.session(output: 40),
      to: workspace.claudeProjects.appending(path: "project/session/subagents/agent.jsonl"),
    )
    let created = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.claude] != 0 }
    #expect(created.snapshot.todayTokens(.claude) == 50)

    let staging = workspace.root.appending(path: "staging", directoryHint: .isDirectory)
    try workspace.write(CodexLog.session(input: 100, output: 20), to: staging.appending(path: "2026/08/25/rollout.jsonl"))
    try FileManager.default.moveItem(
      at: staging.appending(path: "2026"),
      to: workspace.codexSessions.appending(path: "2026"),
    )
    let movedIn = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] != 0 }
    #expect(movedIn.snapshot.todayTokens(.codex) == 120)

    try FileManager.default.removeItem(at: workspace.claudeProjects.appending(path: "project"))
    let removed = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.claude] == 0 }
    #expect(removed.snapshot.todayTokens(.claude) == 0)
  }

  @Test
  func `hidden directories stay unscanned when they change later`() async throws {
    let hidden = workspace.codexSessions.appending(path: ".cache/deep", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    let pipeline = workspace.makePipeline()
    _ = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    try workspace.write(CodexLog.session(input: 100, output: 20, response: "cached"), to: hidden.appending(path: "a.jsonl"))
    try workspace.write(
      CodexLog.session(input: 1, output: 0, response: "witness"),
      to: workspace.codexArchivedSessions.appending(path: "witness.jsonl"),
    )
    let report = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.codex] != 0 }

    #expect(report.ingestion.trackedFiles[.codex] == 1)
    #expect(report.snapshot.todayTokens(.codex) == 1)
  }

  @Test
  func `appearing log root refreshes the report`() async throws {
    let archived = workspace.codexArchivedSessions
    try FileManager.default.removeItem(at: archived)
    let pipeline = workspace.makePipeline()
    let missing = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(missing.ingestion.logRoots.first { $0.path == archived.path }?.exists == false)

    try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
    let appeared = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(appeared.ingestion.logRoots.first { $0.path == archived.path }?.exists == true)
  }

  @Test
  func `hidden files and directories are not scanned`() async throws {
    try workspace.write(
      CodexLog.session(input: 100, output: 20, response: "cached"),
      to: workspace.codexSessions.appending(path: ".cache/a.jsonl"),
    )
    try workspace.write(
      CodexLog.session(input: 100, output: 20, response: "hidden"),
      to: workspace.codexSessions.appending(path: ".b.jsonl"),
    )
    let flagged = workspace.codexSessions.appending(path: "flagged.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20, response: "flagged"), to: flagged)
    #expect(chflags(flagged.path, UInt32(UF_HIDDEN)) == 0)
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.trackedFiles[.codex] == 0)
  }

  private let workspace: UsageTestWorkspace
}
