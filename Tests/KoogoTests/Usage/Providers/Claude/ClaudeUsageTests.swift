import XCTest

@testable import Koogo

final class ClaudeUsageTests: UsageWorkspaceTestCase {
  func testClaudeParsesCacheDurationsSpeedGeoAndSearch() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":10,"cache_read_input_tokens":20,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":30,"ephemeral_1h_input_tokens":40},"speed":"fast","inference_geo":"us","server_tool_use":{"web_search_requests":2}
        """,
    )

    let event = try XCTUnwrap(parser.parse(line)?.event)

    XCTAssertEqual(event.provider, .claude)
    XCTAssertEqual(event.record.processedTokens, 140)
    XCTAssertEqual(event.record.cost.usd, Decimal(string: "0.0236245"))
    XCTAssertEqual(event.record.model, "claude-opus-5")
  }

  func testClaudePreservesAggregateCacheCreationWithoutInventingDuration() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: #""input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40"#,
    )

    let event = try XCTUnwrap(parser.parse(line)?.event)

    XCTAssertEqual(event.record.processedTokens, 120)
    XCTAssertEqual(event.record.cost.usd, Decimal(string: "0.0014875"))
  }

  func testClaudeRejectsInconsistentCacheSplit() {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":10,"cache_creation_input_tokens":70,"output_tokens":40,"cache_creation":{"ephemeral_5m_input_tokens":20,"ephemeral_1h_input_tokens":40}
        """,
    )

    XCTAssertThrowsError(try parser.parse(line))
  }

  func testClaudeRejectsRecordsWithoutBothStableIDs() {
    var parser = ClaudeUsageLogParser()
    let line = """
      {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":40}}}
      """

    XCTAssertThrowsError(try parser.parse(line))
  }

  func testClaudeSkipsZeroUsageSyntheticReplies() throws {
    var parser = ClaudeUsageLogParser()
    let reply = ClaudeLog.assistant(
      model: "<synthetic>",
      usage: #""input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0"#,
    )

    for line in [reply, reply.replacing(#""requestId":"request","#, with: "")] {
      XCTAssertNil(try parser.parse(line), line)
    }
  }

  func testClaudeRejectsOverflowingTokenFields() {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: """
        "input_tokens":0,"cache_creation_input_tokens":18446744073709551615,"output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":18446744073709551615,"ephemeral_1h_input_tokens":1}
        """,
    )

    XCTAssertThrowsError(try parser.parse(line))
  }

  func testClaudeReportsUnpricedModelsAndBilledOptions() throws {
    for (model, usage) in [
      ("unknown-model", #""input_tokens":10,"output_tokens":40"#),
      ("claude-sonnet-4-6", #""input_tokens":10,"output_tokens":40,"speed":"fast""#),
      ("claude-sonnet-4-5", #""input_tokens":10,"output_tokens":40,"inference_geo":"us""#),
      ("claude-opus-5", #""input_tokens":10,"output_tokens":40,"speed":"turbo""#),
    ] {
      var parser = ClaudeUsageLogParser()
      let outcome = try parser.parse(ClaudeLog.assistant(model: model, usage: usage))

      XCTAssertEqual(outcome?.unpricedModel, ModelID(rawValue: model))
    }
  }

  func testClaudeCopyWithMoreExplicitMetadataWinsAtEqualOutput() throws {
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
      let bareCopy = try XCTUnwrap(parser.parse(bare)?.event)
      let detailedCopy = try XCTUnwrap(parser.parse(detailed)?.event)

      for copies in [[bareCopy, detailedCopy], [detailedCopy, bareCopy]] {
        var index = UsageEventIndex()
        index.update { batch in
          for copy in copies {
            batch.insert(copy)
          }
        }
        XCTAssertEqual(index.events.map(\.record.processedTokens), [120], detailed)
      }
    }
  }

  func testColdScanDeduplicatesClaudePartialsAndCopies() async throws {
    try workspace.write(ClaudeLog.session(output: 2), to: workspace.claudeProjects.appending(path: "project/main.jsonl"))
    try workspace.write(
      ClaudeLog.session(output: 40),
      to: workspace.claudeProjects.appending(path: "project/agent/copy.jsonl"),
    )

    let snapshot = await makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    XCTAssertEqual(snapshot.todayTokens(.claude), 50)
  }

  func testClaudeQuotesMatchPublishedRates() throws {
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
      let quote = try XCTUnwrap(ClaudeUsagePricing.quote(model: ModelID(rawValue: model), usage: usage), model)
      XCTAssertEqual(quote.model, ModelID(rawValue: model))
      XCTAssertEqual(quote.cost.usd, Decimal(string: expectedUSD), model)
    }
  }

  func testAbsurdTokenCountsSaturateTheCostInsteadOfTrapping() throws {
    let usage = ClaudeBillableUsage.stub(uncachedInput: .max / 2, output: 1, options: [.fastMode, .usInference])
    let quote = try XCTUnwrap(ClaudeUsagePricing.quote(model: "claude-opus-5", usage: usage))

    XCTAssertEqual(quote.cost, Picodollars(.max))
  }

  func testClaudeSnapshotIDsAndAliasesStartAt45() throws {
    let usage = ClaudeBillableUsage.stub(uncachedInput: 100, output: 10)
    let snapshot = try XCTUnwrap(
      ClaudeUsagePricing.quote(
        model: "claude-sonnet-4-5-20250929",
        usage: usage,
      )
    )
    let alias = try XCTUnwrap(
      ClaudeUsagePricing.quote(model: "claude-sonnet-4-5", usage: usage)
    )

    XCTAssertEqual(snapshot.cost.usd, Decimal(string: "0.00045"))
    XCTAssertEqual(snapshot.cost.usd, alias.cost.usd)
    XCTAssertEqual(alias.model, "claude-sonnet-4-5-20250929")
    XCTAssertNotNil(ClaudeUsagePricing.quote(model: "claude-opus-4-5", usage: usage))
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
      XCTAssertNil(
        ClaudeUsagePricing.quote(
          model: ModelID(rawValue: model),
          usage: ClaudeBillableUsage.stub(uncachedInput: 1),
        )
      )
    }
  }
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
