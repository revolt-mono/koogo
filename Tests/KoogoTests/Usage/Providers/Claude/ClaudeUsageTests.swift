import Foundation
import Testing

@testable import Koogo

struct ClaudeUsageTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `claude parses cache durations speed geo and search`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":30,"ephemeral_1h_input_tokens":40},"speed":"fast","inference_geo":"us","server_tool_use":{"web_search_requests":2}
        """,
    )

    let event = try #require(parser.parse(line)?.event)

    #expect(event.provider == .claude)
    #expect(event.record.processedTokens == 140)
    #expect(event.record.cost.usd == Decimal(string: "0.0236245"))
    #expect(event.record.model == "claude-opus-5")
  }

  @Test
  func `claude preserves aggregate cache creation without inventing duration`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: #""input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40"#,
    )

    let event = try #require(parser.parse(line)?.event)

    #expect(event.record.processedTokens == 120)
    #expect(event.record.cost.usd == Decimal(string: "0.0014875"))
  }

  @Test
  func `claude rejects inconsistent cache split`() {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":40}
        """,
    )

    #expect(throws: (any Error).self) { try parser.parse(line) }
  }

  @Test
  func `claude rejects records without both stable ids`() {
    var parser = ClaudeUsageLogParser()
    let line = """
      {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":40}}}
      """

    #expect(throws: (any Error).self) { try parser.parse(line) }
  }

  @Test
  func `claude identity combines the message and request ids`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":40"#)
    let lines = [
      line,
      line.replacing(#""requestId":"request""#, with: #""requestId":"other""#),
      line.replacing(#""id":"message""#, with: #""id":"other""#),
    ]

    let ids = try lines.map { try #require(parser.parse($0)?.event).id }

    #expect(Set(ids).count == lines.count)
    try #expect(parser.parse(line)?.event?.id == ids[0])
  }

  @Test
  func `claude skips zero usage synthetic replies`() throws {
    var parser = ClaudeUsageLogParser()
    let reply = ClaudeLog.assistant(
      model: "<synthetic>",
      usage: #""input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0"#,
    )

    for line in [reply, reply.replacing(#""requestId":"request","#, with: "")] {
      try #expect(parser.parse(line) == nil, "\(line)")
    }
  }

  @Test
  func `claude skips lines that bill nothing without reading their other fields`() throws {
    var parser = ClaudeUsageLogParser()
    let zeroUsage = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":0,"output_tokens":0"#)
    for line in [
      #"{"timestamp":1,"requestId":2,"message":{"id":3,"model":4,"usage":{"input_tokens":10,"output_tokens":5}}}"#,
      zeroUsage.replacing(#""requestId":"request""#, with: #""requestId":2"#),
      zeroUsage.replacing(#""id":"message""#, with: #""id":3"#),
      zeroUsage.replacing(#""model":"claude-opus-5""#, with: #""model":4"#),
    ] {
      try #expect(parser.parse(line) == nil, "\(line)")
    }
  }

  @Test
  func `claude rejects overflowing token fields`() {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":0,"cache_creation_input_tokens":18446744073709551615,"output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":18446744073709551615,"ephemeral_1h_input_tokens":1}
        """,
    )

    #expect(throws: (any Error).self) { try parser.parse(line) }
  }

  @Test
  func `claude reports unpriced models and billed options`() throws {
    for (model, usage) in [
      ("unknown-model", #""input_tokens":10,"output_tokens":40"#),
      ("claude-sonnet-4-6", #""input_tokens":10,"output_tokens":40,"speed":"fast""#),
      ("claude-sonnet-4-5", #""input_tokens":10,"output_tokens":40,"inference_geo":"us""#),
      ("claude-opus-5", #""input_tokens":10,"output_tokens":40,"speed":"turbo""#),
    ] {
      var parser = ClaudeUsageLogParser()
      let outcome = try parser.parse(ClaudeLog.assistant(model: model, usage: usage))

      #expect(outcome?.unpricedModel == ModelID(rawValue: model))
    }
  }

  @Test
  func `claude copy with more explicit metadata wins at equal output`() throws {
    let tokens = #""input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40"#
    let bare = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: #""input_tokens":11,"cache_creation_input_tokens":70,"output_tokens":40"#,
    )

    for detailed in [
      ClaudeLog.assistant(model: "claude-opus-5", usage: tokens + #","speed":"standard""#),
      ClaudeLog.assistant(
        model: "claude-opus-5",
        usage: tokens + #","cache_creation":{"ephemeral_5m_input_tokens":70}"#,
      ),
    ] {
      var parser = ClaudeUsageLogParser()
      let bareCopy = try #require(parser.parse(bare)?.event)
      let detailedCopy = try #require(parser.parse(detailed)?.event)

      for copies in [[bareCopy, detailedCopy], [detailedCopy, bareCopy]] {
        var index = UsageEventIndex()
        index.update { batch in
          for copy in copies {
            batch.insert(copy)
          }
        }
        #expect(index.events.map(\.record.processedTokens) == [120], "\(detailed)")
      }
    }
  }

  @Test
  func `cold scan deduplicates claude partials and copies`() async throws {
    try workspace.write(ClaudeLog.session(output: 2), to: workspace.claudeProjects.appending(path: "project/main.jsonl"))
    try workspace.write(
      ClaudeLog.session(output: 40),
      to: workspace.claudeProjects.appending(path: "project/agent/copy.jsonl"),
    )

    let snapshot = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.todayTokens(.claude) == 50)
  }

  @Test
  func `claude quotes match published rates`() throws {
    let usage = { (options: ClaudeBillableUsage.Options) in
      ClaudeBillableUsage.stub(
        uncachedInput: 100_000,
        cachedInput: 100_000,
        cacheWrite5MinuteInput: 100_000,
        cacheWrite1HourInput: 100_000,
        output: 10_000,
        options: options,
      )
    }
    let standard = usage([])
    let fast = usage([.fastMode])
    let usInference = usage([.usInference])
    let shortPrompt = ClaudeBillableUsage.stub(uncachedInput: 50_000, cachedInput: 50_000, output: 10_000)

    for (model, usage, expectedUSD) in [
      ("claude-fable-5-2", fast, "7.64"),
      ("claude-opus-5", standard, "2.425"),
      ("claude-opus-5", fast, "4.85"),
      ("claude-sonnet-5", standard, "0.97"),
      ("claude-sonnet-5", usInference, "1.067"),
      ("claude-haiku-5-5", shortPrompt, "0.0105"),
      ("claude-haiku-5-5", standard, "0.2425"),
      ("claude-haiku-5-5", usInference, "0.26675"),
    ] {
      let quote = try #require(ClaudeUsagePricing.quote(model: ModelID(rawValue: model), usage: usage), "\(model)")
      #expect(quote.model == ModelID(rawValue: model))
      #expect(quote.cost.usd == Decimal(string: expectedUSD), "\(model)")
    }
  }

  @Test
  func `absurd token counts saturate the cost instead of trapping`() throws {
    let usage = ClaudeBillableUsage.stub(uncachedInput: .max / 2, output: 1, options: [.fastMode, .usInference])
    let quote = try #require(ClaudeUsagePricing.quote(model: "claude-opus-5", usage: usage))

    #expect(quote.cost == Picodollars(.max))
  }

  @Test
  func `claude snapshot ids and aliases start at 45`() throws {
    let usage = ClaudeBillableUsage.stub(uncachedInput: 100, output: 10)
    let snapshot = try #require(
      ClaudeUsagePricing.quote(
        model: "claude-sonnet-4-5-20250929",
        usage: usage,
      )
    )
    let alias = try #require(
      ClaudeUsagePricing.quote(model: "claude-sonnet-4-5", usage: usage)
    )

    #expect(snapshot.cost.usd == Decimal(string: "0.00045"))
    #expect(snapshot.cost.usd == alias.cost.usd)
    #expect(alias.model == "claude-sonnet-4-5-20250929")
    #expect(ClaudeUsagePricing.quote(model: "claude-opus-4-5", usage: usage) != nil)
    for model in [
      "claude-opus-4-1-20250805",
      "claude-opus-4-1",
      "claude-opus-4-20250514",
      "claude-opus-4-0",
      "claude-sonnet-4-20250514",
      "claude-sonnet-4-0",
      "claude-haiku-4-5-20251001",
      "claude-haiku-4-5",
      "claude-3-5-haiku-20241022",
      "claude-3-5-haiku-latest",
    ] {
      #expect(
        ClaudeUsagePricing.quote(
          model: ModelID(rawValue: model),
          usage: ClaudeBillableUsage.stub(uncachedInput: 1),
        )
          == nil
      )
    }
  }

  private let workspace: UsageTestWorkspace
}

extension ClaudeBillableUsage {
  fileprivate static func stub(
    uncachedInput: UInt64 = 0,
    cachedInput: UInt64 = 0,
    cacheWrite5MinuteInput: UInt64 = 0,
    cacheWrite1HourInput: UInt64 = 0,
    output: UInt64 = 0,
    options: ClaudeBillableUsage.Options = [],
  ) -> Self {
    guard
      let tokens = ClaudeTokenUsage(
        input: uncachedInput,
        cacheRead: cachedInput,
        cacheCreation: .byDuration(
          fiveMinute: cacheWrite5MinuteInput,
          oneHour: cacheWrite1HourInput,
        ),
        output: output,
      )
    else {
      preconditionFailure("invalid claude usage fixture")
    }
    return ClaudeBillableUsage(tokens: tokens, options: options, webSearchRequests: 0)
  }
}
