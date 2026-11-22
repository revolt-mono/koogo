import Foundation
import Testing

@testable import Koogo

struct CodexUsageTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `codex bills each response record under the turn model`() throws {
    var parser = CodexUsageLogParser()
    try #expect(parser.parse(CodexLog.meta()) == nil)
    try #expect(parser.parse(CodexLog.turn()) == nil)

    let request = CodexLog.usage(input: 100, output: 20)
    let first = try #require(parser.parse(CodexLog.tokenUsageRecord(request))?.event)
    let second = try #require(
      parser.parse(
        CodexLog.tokenUsageRecord(CodexLog.usage(input: 150, output: 30), response: "second")
      )?.event
    )

    #expect(first.record.processedTokens == 120)
    #expect(second.record.processedTokens == 180)
    #expect(second.record.model == "gpt-5.6-sol")
    #expect(first.id != second.id)
  }

  @Test
  func `codex records before the first turn context are skipped`() throws {
    var parser = CodexUsageLogParser()
    let request = CodexLog.usage(input: 100, output: 20)
    try #expect(parser.parse(CodexLog.meta()) == nil)
    try #expect(parser.parse(CodexLog.tokenUsageRecord(request)) == nil)
    try #expect(parser.parse(CodexLog.turn()) == nil)

    let event = try #require(parser.parse(CodexLog.tokenUsageRecord(CodexLog.usage(input: 50, output: 10)))?.event)

    #expect(event.record.processedTokens == 60)
  }

  @Test
  func `malformed turn contexts do not reuse the previous model`() async throws {
    for context in [
      #"{"type":"turn_context"}"#,
      #"{"type":"turn_context","payload":null}"#,
      #"{"type":"turn_context","payload":{}}"#,
      #"{"type":"turn_context","payload":{"model":12}}"#,
      #"{"type":"turn_context","payload":{"model":""}}"#,
    ] {
      let request = CodexLog.usage(input: 100, output: 20)
      try workspace.write(
        [
          CodexLog.session(input: 100, output: 20, response: "before"),
          context,
          CodexLog.tokenUsageRecord(request, response: "invalid"),
          CodexLog.session(input: 50, output: 10, response: "after", model: "gpt-6-luna"),
        ].joined(separator: "\n"),
        to: workspace.codexSessions.appending(path: "session.jsonl"),
      )

      let report = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: [.codex])

      #expect(report.ingestion.malformedLines[.codex] == 1, "\(context)")
      #expect(report.ingestion.unpricedModels.isEmpty, "\(context)")
      #expect(report.ingestion.events[.codex] == 2, "\(context)")
      #expect(report.snapshot.todayTokens(.codex) == 180, "\(context)")
      #expect(
        report.snapshot.providers[.codex]?.periods[.today].total.cost.usd == Decimal(string: "0.00111"),
        "\(context)",
      )
    }
  }

  @Test
  func `codex rejects records missing usage or timestamp`() throws {
    var parser = try parserInTurn()
    let request = CodexLog.usage(input: 100, output: 20)
    let record = CodexLog.tokenUsageRecord(request)
    let undated = record.replacing(#""timestamp":"\#(UsageFixture.timestampText)","#, with: "")
    var outsideTurn = CodexUsageLogParser()

    #expect(throws: (any Error).self) {
      try parser.parse(record.replacing(#""usage":\#(request),"#, with: ""))
    }
    #expect(throws: (any Error).self) { try parser.parse(undated) }
    #expect(throws: (any Error).self) { try outsideTurn.parse(undated) }
    try #expect(parser.parse(record)?.event?.record.processedTokens == 120)
  }

  @Test
  func `codex rejects malformed output tokens`() throws {
    for outputTokens in ["\"20\"", "true", "18446744073709551616"] {
      var parser = try parserInTurn()
      let request = CodexLog.usage(input: 100, output: 20)
      let line = CodexLog.tokenUsageRecord(request)

      #expect(throws: (any Error).self) {
        try parser.parse(
          line.replacing("\"output_tokens\":20", with: "\"output_tokens\":\(outputTokens)")
        )
      }
      let event = try #require(parser.parse(line)?.event)
      #expect(event.record.processedTokens == 120)
    }
  }

  @Test
  func `codex thread settings do not override turn usage metadata`() throws {
    var parser = try parserInTurn()
    let settings = """
      {"timestamp":"2026-08-25T12:00:00.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-5.6-luna","reasoning_effort":"low","service_tier":"priority"}}}
      """
    try #expect(parser.parse(settings) == nil)
    let request = CodexLog.usage(input: 100, output: 20)
    let event = try #require(parser.parse(CodexLog.tokenUsageRecord(request))?.event)

    #expect(event.record.model == "gpt-5.6-sol")
  }

  @Test
  func `codex prices logged cache writes`() throws {
    for (model, expectedUSD) in [
      ("gpt-5.6-sol", "0.0010925"),
      ("gpt-6.1-sol", "0.000396"),
      ("gpt-6.2-astra", "0.001584"),
      ("gpt-6.2-sol", "0.000396"),
    ] {
      var parser = try parserInTurn(model: model)
      let request = CodexLog.usage(input: 100, output: 20, cached: 10, cacheWrite: 30)
      let event = try #require(parser.parse(CodexLog.tokenUsageRecord(request))?.event)

      #expect(event.record.processedTokens == 120)
      #expect(event.record.model?.rawValue == model)
      #expect(event.record.cost.usd == Decimal(string: expectedUSD), "\(model)")
    }
  }

  @Test
  func `codex rejects overflowing token fields`() throws {
    var parser = try parserInTurn()
    let overflow = """
      {"input_tokens":18446744073709551615,"cached_input_tokens":18446744073709551615,"cache_write_input_tokens":1,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":18446744073709551615}
      """

    #expect(throws: (any Error).self) { try parser.parse(CodexLog.tokenUsageRecord(overflow)) }
  }

  @Test
  func `codex reports unpriced models and unsupported cache writes`() throws {
    func outcome(model: String, cacheWrite: Int = 0) throws -> UsageLineOutcome? {
      var parser = try parserInTurn(model: model)
      let request = CodexLog.usage(input: 100, output: 20, cacheWrite: cacheWrite)
      return try parser.parse(CodexLog.tokenUsageRecord(request))
    }

    try #expect(outcome(model: "unknown-model")?.unpricedModel == "unknown-model")
    try #expect(outcome(model: "gpt-5.5", cacheWrite: 1)?.unpricedModel == "gpt-5.5")
    try #expect(outcome(model: "gpt-5.5")?.event != nil)
  }

  @Test
  func `codex identical request usage at the same timestamp counts twice`() async throws {
    let request = CodexLog.usage(input: 50, output: 10)
    try workspace.write(
      [
        CodexLog.meta(),
        CodexLog.turn(),
        CodexLog.tokenUsageRecord(request),
        CodexLog.tokenUsageRecord(request, response: "second"),
        "",
      ].joined(separator: "\n"),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )

    let snapshot = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.todayTokens(.codex) == 120)
  }

  @Test
  func `codex quotes match published rates`() throws {
    let short = CodexTokenUsage.stub(uncached: 100_000, cached: 100_000, cacheWrite: 50_000, output: 10_000)
    let long = CodexTokenUsage.stub(uncached: 122_001, cached: 100_000, cacheWrite: 50_000, output: 10_000)
    let shortWithoutWrites = CodexTokenUsage.stub(uncached: 150_000, cached: 100_000, output: 10_000)
    let longWithoutWrites = CodexTokenUsage.stub(uncached: 172_001, cached: 100_000, output: 10_000)

    for (model, tokens, expectedUSD) in [
      ("gpt-6.2-astra", long, "3.632016"),
      ("gpt-6.2-sol", long, "0.908004"),
      ("gpt-6.1-sol", short, "0.435"),
      ("gpt-6.1-sol", long, "0.908004"),
      ("gpt-5.5", shortWithoutWrites, "1.1"),
      ("gpt-5.5", longWithoutWrites, "2.27001"),
      ("gpt-5.4-mini", shortWithoutWrites, "0.165"),
      ("gpt-5.4-mini", longWithoutWrites, "0.18150075"),
    ] {
      let quote = try #require(CodexUsagePricing.quote(model: ModelID(rawValue: model), tokens: tokens), "\(model)")
      #expect(quote.model == ModelID(rawValue: model))
      #expect(quote.cost.usd == Decimal(string: expectedUSD), "\(model)")
    }
  }

  @Test
  func `codex long context rates apply to the whole request`() throws {
    let atBoundary = try #require(
      CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: CodexTokenUsage.stub(uncached: 272_000))
    )
    let long = try #require(
      CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: CodexTokenUsage.stub(uncached: 272_001))
    )

    #expect(atBoundary.cost.usd == Decimal(string: "1.36"))
    #expect(long.cost.usd == Decimal(string: "2.72001"))
  }

  @Test
  func `codex alias resolves to canonical model`() throws {
    let tokens = CodexTokenUsage.stub(uncached: 1)
    let canonical = try #require(CodexUsagePricing.quote(model: "gpt-5.6-sol", tokens: tokens))
    let alias = try #require(CodexUsagePricing.quote(model: "gpt-5.6", tokens: tokens))

    #expect(alias.model == canonical.model)
  }

  private let workspace: UsageTestWorkspace

  private func parserInTurn(model: String = "gpt-5.6-sol") throws -> CodexUsageLogParser {
    var parser = CodexUsageLogParser()
    _ = try parser.parse(CodexLog.meta())
    _ = try parser.parse(CodexLog.turn(model: model))
    return parser
  }
}

extension CodexTokenUsage {
  fileprivate static func stub(
    uncached: UInt64,
    cached: UInt64 = 0,
    cacheWrite: UInt64 = 0,
    output: UInt64 = 0,
  ) -> Self {
    guard
      let usage = CodexTokenUsage(
        input: uncached + cached + cacheWrite,
        cachedInput: cached,
        cacheWrite: cacheWrite,
        output: output,
        processed: uncached + cached + cacheWrite + output,
      )
    else {
      preconditionFailure("invalid codex usage fixture")
    }
    return usage
  }
}
