import Foundation
import Testing

@testable import Koogo

struct UsagePipelineTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `cold scan loads every file across parallel readers`() async throws {
    let usage = CodexLog.usage(input: 100, output: 20)
    for index in 0..<19 {
      try workspace.write(
        [
          CodexLog.turn(),
          CodexLog.tokenUsageRecord(usage, response: "response-\(index)"),
          "",
        ].joined(separator: "\n"),
        to: workspace.codexSessions.appending(path: "session-\(index).jsonl"),
      )
    }
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.trackedFiles[.codex] == 19)
    #expect(report.ingestion.events[.codex] == 19)
    #expect(report.snapshot.todayTokens(.codex) == 2_280)
  }

  @Test
  func `unicode and reserved characters in log paths`() async throws {
    let log = workspace.codexSessions.appending(path: "项目 #100%/session ?.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20), to: log)
    let pipeline = workspace.makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    #expect(initial.ingestion.trackedFiles[.codex] == 1)
    #expect(initial.snapshot.todayTokens(.codex) == 120)

    try workspace.append(
      CodexLog.tokenUsageRecord(
        CodexLog.usage(input: 50, output: 10),
        response: "second",
      ) + "\n",
      to: log,
    )
    let appended = try await workspace.refresh(pipeline) { $0.snapshot.todayTokens(.codex) != 120 }
    #expect(appended.ingestion.trackedFiles[.codex] == 1)
    #expect(appended.snapshot.todayTokens(.codex) == 180)
  }

  @Test
  func `disabled providers are neither scanned nor summarized`() async throws {
    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    try workspace.write(ClaudeLog.session(output: 40), to: workspace.claudeProjects.appending(path: "main.jsonl"))
    let pipeline = workspace.makePipeline()

    let all = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    let codexOnly = await pipeline.run(at: UsageFixture.timestamp, providers: [.codex])
    let codexAndGrok = await pipeline.run(at: UsageFixture.timestamp, providers: [.codex, .grok])

    #expect(all.snapshot.summary.today.current.processedTokens == 170)
    #expect(Set(codexOnly.snapshot.providers.keys) == [.codex])
    #expect(codexOnly.snapshot.summary.today.current.processedTokens == 120)
    #expect(codexOnly.ingestion.trackedFiles[.claude] == 0)
    #expect(Set(codexAndGrok.snapshot.providers.keys) == [.codex, .grok])
  }

  @Test
  func `refresh moves rolling windows only at midnight`() async throws {
    for (index, timestamp) in [
      "2026-06-27T00:00:00Z",
      "2026-07-27T00:00:00Z",
      "2026-08-19T00:00:00Z",
      "2026-08-25T00:00:00Z",
    ].enumerated() {
      try workspace.write(
        CodexLog.session(input: 1 << index, output: 0, response: "boundary-\(index)", usageTimestamp: timestamp),
        to: workspace.codexSessions.appending(path: "boundary-\(index).jsonl"),
      )
    }
    let pipeline = workspace.makePipeline()
    let current = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)
    let lastMillisecond = try Date("2026-08-25T23:59:59.999Z", strategy: .iso8601)
    let evening = await pipeline.run(at: lastMillisecond, providers: Provider.allCases)
    let midnight = try Date("2026-08-26T00:00:00Z", strategy: .iso8601)
    let refreshed = await pipeline.run(at: midnight, providers: Provider.allCases)

    #expect(current.ingestion.events[.codex] == 3)
    #expect(current.snapshot.todayTokens(.codex) == 8)
    #expect(current.snapshot.providers[.codex]?.periods[.last7Days].total.processedTokens == 12)
    #expect(current.snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens == 14)
    #expect(evening.snapshot == current.snapshot)
    #expect(refreshed.ingestion.events[.codex] == 2)
    #expect(refreshed.snapshot.providers[.codex]?.periods[.today].total == UsagePeriodSnapshot())
    #expect(refreshed.snapshot.providers[.codex]?.periods[.last7Days].total.processedTokens == 8)
    #expect(refreshed.snapshot.providers[.codex]?.periods[.last30Days].total.processedTokens == 12)
    #expect(refreshed.snapshot.summary.last7Days.costChange == .increase(fraction: 1))
  }

  @Test
  func `unpriced model is excluded from totals and reported`() async throws {
    let log = workspace.codexSessions.appending(path: "session.jsonl")
    try workspace.write(CodexLog.session(input: 100, output: 20, model: "unknown-model"), to: log)
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.snapshot.providers[.codex]?.periods[.last30Days].total == UsagePeriodSnapshot())
    #expect(report.ingestion.trackedFiles == [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
    #expect(report.ingestion.events == [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
    #expect(report.ingestion.unpricedModels == ["unknown-model"])
  }

  @Test
  func `cold scan compares with the previous 7 days and discards older history`() async throws {
    try workspace.write(
      CodexLog.session(
        input: 100,
        output: 20,
        response: "previous-day",
        usageTimestamp: "2026-08-24T17:00:00.000Z",
      ),
      to: workspace.codexSessions.appending(path: "previous-day.jsonl"),
    )
    try workspace.write(
      CodexLog.session(
        input: 200,
        output: 40,
        response: "previous-7-days",
        usageTimestamp: "2026-08-18T17:00:00.000Z",
      ),
      to: workspace.codexSessions.appending(path: "previous-7-days.jsonl"),
    )
    for index in 1...3 {
      try workspace.write(
        CodexLog.session(
          input: 1,
          output: 0,
          response: "older-\(index)",
          model: "gpt-5.6-luna",
          usageTimestamp: "2026-07-26T23:59:59.999Z",
        ),
        to: workspace.codexSessions.appending(path: "older-\(index).jsonl"),
      )
    }
    let pipeline = workspace.makePipeline()

    let report = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.events[.codex] == 2)
    #expect(report.snapshot.summary.today.costChange == .decrease(fraction: 1))
    #expect(report.snapshot.summary.last7Days.costChange == .decrease(fraction: Decimal(1) / 2))
  }

  @Test
  func `records beside billed ones are skipped`() async throws {
    let request = CodexLog.usage(input: 100, output: 20)
    try workspace.write(
      [
        CodexLog.meta(),
        """
        {"timestamp":"2026-08-25T11:31:00.000Z","ordinal":2,"type":"response_item","payload":{"type":"function_call","name":"token_count"}}
        """,
        """
        {"timestamp":"2026-08-25T11:32:00.000Z","ordinal":3,"type":"event_msg","payload":{"type":"item_completed","item":{}}}
        """,
        CodexLog.turn(),
        CodexLog.tokenUsageRecord(request),
        "",
      ].joined(separator: "\n"),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    try workspace.write(
      [
        """
        {"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":"assistant usage"}}
        """,
        #"{"parentUuid":"u","isSidechain":false,"attachment":{"type":"file"},"type":"attachment"}"#,
        ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":40"#),
        "",
      ].joined(separator: "\n"),
      to: workspace.claudeProjects.appending(path: "project/session.jsonl"),
    )

    let report = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases)

    #expect(report.ingestion.malformedLines == [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
    #expect(report.ingestion.events == [.codex: 1, .claude: 1, .piAgent: 0, .grok: 0])
  }

  private let workspace: UsageTestWorkspace
}
