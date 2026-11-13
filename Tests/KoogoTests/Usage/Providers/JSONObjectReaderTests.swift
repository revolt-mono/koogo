import XCTest

@testable import Koogo

final class JSONObjectReaderTests: XCTestCase {
  func testCodexReadsRecordsWhoseKindDoesNotLeadTheLine() throws {
    var parser = CodexUsageLogParser()
    let request = CodexLog.usage(input: 100, output: 20)
    XCTAssertNil(
      try parser.parse(
        #"{"payload":{"turn_id":"turn","model":"gpt-5.6-sol","effort":"high"},"type":"turn_context"}"#
      )
    )

    let event = try XCTUnwrap(
      try parser.parse(
        """
        { "timestamp": "2026-08-25T12:00:00.000Z", "payload": {"usage":\(request),"response_id":"response"}, "type": "token_usage_record" }
        """
      )?.event
    )

    XCTAssertEqual(event.record.processedTokens, 120)
    XCTAssertEqual(event.record.model, "gpt-5.6-sol")
  }

  func testSkippedValuesMayHoldEscapesAndBrackets() throws {
    var parser = ClaudeUsageLogParser()
    let content = #"""
      [{"type":"text","text":"a \"quoted\" } ] { [ path\\\\"},{"type":"tool_use","input":{"k":[1,{"v":"\\\""}]}}]
      """#
    let line = #"""
      {"parentUuid":null,"message":{"id":"message","model":"claude-opus-5","content":\#(content),\#
      "usage":{"input_tokens":10,"output_tokens":5}},"requestId":"request","type":"assistant",\#
      "timestamp":"2026-08-25T12:00:00.000Z"}
      """#

    XCTAssertEqual(try XCTUnwrap(parser.parse(line)?.event).record.processedTokens, 15)
  }

  func testEscapedKeysAndRecordKindsMatchDecodedText() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
      .replacing(#""type":"assistant""#, with: #""ty\u0070e":"ass\u0069stant""#)
      .replacing(#""input_tokens""#, with: #""input_\u0074okens""#)

    XCTAssertEqual(try XCTUnwrap(parser.parse(line)?.event).record.processedTokens, 15)
  }

  func testEscapedIdentitiesAndTimestampsMatchTheirDecodedText() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
    let escaped =
      line
        .replacing(#""id":"message""#, with: #""id":"mess\u0061ge""#)
        .replacing(#""requestId":"request""#, with: #""requestId":"\u0072equest""#)
        .replacing(
          UsageFixture.timestampText,
          with: UsageFixture.timestampText.replacing("T", with: #"\u0054"#),
        )

    let plain = try XCTUnwrap(parser.parse(line)?.event)
    let decoded = try XCTUnwrap(parser.parse(escaped)?.event)
    XCTAssertEqual(decoded.id, plain.id)
    XCTAssertEqual(decoded.record.timestamp, plain.record.timestamp)
  }

  func testSimilarAndNonStringRecordKindsAreSkipped() throws {
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
    for kind in [#""assistant-extra""#, #""assistanx""#, #""assistant\t""#, "null", "1", #"["assistant"]"#] {
      var parser = ClaudeUsageLogParser()
      let changed = line.replacing(#""type":"assistant""#, with: "\"type\":\(kind)")
      XCTAssertNil(try parser.parse(changed), kind)
    }
  }

  func testWholeNumbersInAnyJSONFormAreRead() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: #""input_tokens":1e1,"output_tokens":5.0,"cache_read_input_tokens":0e0"#,
    )

    XCTAssertEqual(try XCTUnwrap(parser.parse(line)?.event).record.processedTokens, 15)
  }

  func testIntegersInUnusualFormsAreReadAsJSON() throws {
    var parser = PiUsageLogParser()
    for (usage, tokens) in [
      (#"{"totalTokens":-0,"cost":{"total":0.01}}"#, UInt64(0)),
      (#"{"totalTokens":100000000000000000000e-20,"cost":{"total":0.01}}"#, 1),
    ] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
      XCTAssertEqual(try XCTUnwrap(parser.parse(line)?.event, usage).record.processedTokens, tokens)
    }
  }

  func testLoggedDollarsRoundHalfUpToWholePicodollars() throws {
    var parser = PiUsageLogParser()
    for (cost, picodollars) in [
      ("0.125", UInt64(125_000_000_000)),
      ("1.2e-5", 12_000_000),
      ("12E+1", 120_000_000_000_000),
      ("0.0000000000015", 2),
      ("0.0000000000014999", 1),
      ("0.12345678901234567", 123_456_789_012),
      ("1e-40", 0),
    ] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: cost))
      let event = try XCTUnwrap(parser.parse(line)?.event, cost)
      XCTAssertEqual(event.record.cost, Picodollars(picodollars), cost)
    }
    for cost in ["-0.01", "1e30", "0.12345678901234567890123"] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: cost))
      XCTAssertThrowsError(try parser.parse(line), cost)
    }
  }

  func testMalformedReadValuesMakeARecordMalformed() throws {
    var parser = PiUsageLogParser()
    for usage in [
      #"{"totalTokens":01,"cost":{"total":0.01}}"#,
      #"{"totalTokens":1,"cost":{"total":00.01}}"#,
      #"{"totalTokens":1,"cost":{"total":1.}}"#,
      #"{"totalTokens":1,"cost":{"total":0.01 "extra":0}}"#,
    ] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
      XCTAssertThrowsError(try parser.parse(line), usage)
    }
    let tabbedID = PiLog.assistant(id: "re\tply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: "0"))
    XCTAssertThrowsError(try parser.parse(tabbedID))
    var invalidUTF8 = Data(
      PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: "0")).utf8
    )
    invalidUTF8.replaceSubrange(try XCTUnwrap(invalidUTF8.range(of: Data("reply".utf8))), with: [0x72, 0xFF])
    XCTAssertThrowsError(try invalidUTF8.withUnsafeBytes { try parser.parse($0) })
  }

  func testTrailingDataMakesARecordMalformed() {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)

    XCTAssertThrowsError(try parser.parse(line + " garbage"))
    XCTAssertNotNil(try parser.parse(line + " \t"))
  }
}
