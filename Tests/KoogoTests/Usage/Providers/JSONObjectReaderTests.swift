import Foundation
import Testing

@testable import Koogo

struct JSONObjectReaderTests {
  @Test
  func `codex reads records whose kind does not lead the line`() throws {
    var parser = CodexUsageLogParser()
    let request = CodexLog.usage(input: 100, output: 20)
    try #expect(
      parser.parse(#"{"payload":{"turn_id":"turn","model":"gpt-5.6-sol","effort":"high"},"type":"turn_context"}"#) == nil
    )

    let event = try #require(
      parser.parse(
        """
        { "timestamp": "2026-08-25T12:00:00.000Z", "payload": {"usage":\(request),"response_id":"response"}, "type": "token_usage_record" }
        """
      )?.event
    )

    #expect(event.record.processedTokens == 120)
    #expect(event.record.model == "gpt-5.6-sol")
  }

  @Test
  func `skipped values may hold escapes and brackets`() throws {
    var parser = ClaudeUsageLogParser()
    let content = #"""
      [{"type":"text","text":"a \"quoted\" } ] { [ path\\\\"},{"type":"tool_use","input":{"k":[1,{"v":"\\\""}]}}]
      """#
    let line = #"""
      {"parentUuid":null,"message":{"id":"message","model":"claude-opus-5","content":\#(content),\#
      "usage":{"input_tokens":10,"output_tokens":5}},"requestId":"request","type":"assistant",\#
      "timestamp":"2026-08-25T12:00:00.000Z"}
      """#

    try #expect(parser.parse(line)?.event?.record.processedTokens == 15)
  }

  @Test
  func `escaped keys and record kinds match decoded text`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
      .replacing(#""type":"assistant""#, with: #""ty\u0070e":"ass\u0069stant""#)
      .replacing(#""input_tokens""#, with: #""input_\u0074okens""#)

    try #expect(parser.parse(line)?.event?.record.processedTokens == 15)
  }

  @Test
  func `escaped identities and timestamps match their decoded text`() throws {
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

    let plain = try #require(parser.parse(line)?.event)
    let decoded = try #require(parser.parse(escaped)?.event)
    #expect(decoded.id == plain.id)
    #expect(decoded.record.timestamp == plain.record.timestamp)
  }

  @Test
  func `unescaped unicode text matches its escaped spelling`() throws {
    var parser = PiUsageLogParser()
    let line = PiLog.assistant(id: "réponse", parentID: nil, model: "modèle", usage: PiLog.usage(input: 1, cost: "0.01"))
    let escaped = line.replacing("réponse", with: #"r\u00e9ponse"#).replacing("modèle", with: #"mod\u00e8le"#)

    let plain = try #require(parser.parse(line)?.event)
    let decoded = try #require(parser.parse(escaped)?.event)
    #expect(plain.record.model == "provider/modèle")
    #expect(decoded.record.model == plain.record.model)
    #expect(decoded.id == plain.id)
  }

  @Test
  func `similar and non string record kinds are skipped`() throws {
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
    for kind in [#""assistant-extra""#, #""assistanx""#, #""assistant\t""#, "null", "1", #"["assistant"]"#] {
      var parser = ClaudeUsageLogParser()
      let changed = line.replacing(#""type":"assistant""#, with: "\"type\":\(kind)")
      try #expect(parser.parse(changed) == nil, "\(kind)")
    }
  }

  @Test
  func `whole numbers in any json form are read`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(
      model: "claude-opus-5",
      usage: #""input_tokens":1e1,"output_tokens":5.0,"cache_read_input_tokens":0e0"#,
    )

    try #expect(parser.parse(line)?.event?.record.processedTokens == 15)
  }

  @Test
  func `integers in unusual forms are read as json`() throws {
    var parser = PiUsageLogParser()
    for (usage, tokens) in [
      (#"{"totalTokens":-0,"cost":{"total":0.01}}"#, UInt64(0)),
      (#"{"totalTokens":100000000000000000000e-20,"cost":{"total":0.01}}"#, 1),
    ] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
      try #expect(parser.parse(line)?.event?.record.processedTokens == tokens, "\(usage)")
    }
  }

  @Test
  func `logged dollars round half up to whole picodollars`() throws {
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
      let event = try #require(parser.parse(line)?.event, "\(cost)")
      #expect(event.record.cost == Picodollars(picodollars), "\(cost)")
    }
    for cost in ["-0.01", "1e30", "0.12345678901234567890123"] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: cost))
      #expect(throws: (any Error).self, "\(cost)") { try parser.parse(line) }
    }
  }

  @Test
  func `malformed read values make a record malformed`() throws {
    var parser = PiUsageLogParser()
    for usage in [
      #"{"totalTokens":01,"cost":{"total":0.01}}"#,
      #"{"totalTokens":1,"cost":{"total":00.01}}"#,
      #"{"totalTokens":1,"cost":{"total":1.}}"#,
      #"{"totalTokens":1,"cost":{"total":0.01 "extra":0}}"#,
    ] {
      let line = PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
      #expect(throws: (any Error).self, "\(usage)") { try parser.parse(line) }
    }
    let tabbedID = PiLog.assistant(id: "re\tply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: "0"))
    #expect(throws: (any Error).self) { try parser.parse(tabbedID) }
    var invalidUTF8 = Data(
      PiLog.assistant(id: "reply", parentID: nil, model: "model-a", usage: PiLog.usage(input: 1, cost: "0")).utf8
    )
    invalidUTF8.replaceSubrange(try #require(invalidUTF8.range(of: Data("reply".utf8))), with: [0x72, 0xFF])
    #expect(throws: (any Error).self) { try invalidUTF8.withUnsafeBytes { try parser.parse($0) } }
  }

  @Test
  func `trailing data makes a record malformed`() throws {
    var parser = ClaudeUsageLogParser()
    let line = ClaudeLog.assistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)

    #expect(throws: (any Error).self) { try parser.parse(line + " garbage") }
    try #expect(parser.parse(line + " \t") != nil)
  }
}
