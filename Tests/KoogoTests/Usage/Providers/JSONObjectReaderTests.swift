import Foundation
import XCTest

@testable import Koogo

final class JSONObjectReaderTests: XCTestCase {
    func testCodexReadsRecordsWhoseKindDoesNotLeadTheLine() throws {
        var parser = CodexLogParser()
        let request = codexUsage(input: 100, output: 20)
        XCTAssertNil(
            try parse(
                #"{"payload":{"turn_id":"turn","model":"gpt-5.6-sol","effort":"high"},"type":"turn_context"}"#,
                with: &parser
            )
        )

        let event = try XCTUnwrap(
            try parse(
                """
                { "timestamp": "2026-08-25T12:00:00.000Z", "type": "event_msg", "payload": {"info":{"last_token_usage":\(request),"total_token_usage":\(request)},"type":"token_count"} }
                """,
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.record.processedTokens, 120)
        XCTAssertEqual(event.record.modelTurn?.reasoningEffort, "high")
    }

    func testSkippedValuesMayHoldEscapesAndBrackets() throws {
        var parser = ClaudeLogParser()
        let content = #"""
            [{"type":"text","text":"a \"quoted\" } ] { [ path\\\\"},{"type":"tool_use","input":{"k":[1,{"v":"\\\""}]}}]
            """#
        let line = #"""
            {"parentUuid":null,"message":{"id":"message","model":"claude-opus-5","content":\#(content),\#
            "usage":{"input_tokens":10,"output_tokens":5}},"requestId":"request","type":"assistant",\#
            "timestamp":"2026-08-25T12:00:00.000Z"}
            """#

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).record.processedTokens, 15)
    }

    func testEscapedKeysAndRecordKindsMatchDecodedText() throws {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
            .replacingOccurrences(of: #""type":"assistant""#, with: #""ty\u0070e":"ass\u0069stant""#)
            .replacingOccurrences(of: #""input_tokens""#, with: #""input_\u0074okens""#)

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).record.processedTokens, 15)
    }

    func testSimilarAndNonStringRecordKindsAreSkipped() throws {
        let line = claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
        for kind in [#""assistant-extra""#, #""assistanx""#, #""assistant\t""#, "null", "1", #"["assistant"]"#] {
            var parser = ClaudeLogParser()
            let changed = line.replacingOccurrences(of: #""type":"assistant""#, with: "\"type\":\(kind)")
            XCTAssertNil(try parse(changed, with: &parser), kind)
        }
    }

    func testWholeNumbersInAnyJSONFormAreRead() throws {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(
            model: "claude-opus-5",
            usage: #""input_tokens":1e1,"output_tokens":5.0,"cache_read_input_tokens":0e0"#
        )

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).record.processedTokens, 15)
    }

    func testIntegersInUnusualFormsAreReadAsJSON() throws {
        var parser = PiLogParser()
        for (usage, tokens) in [
            (#"{"totalTokens":-0,"cost":{"total":0.01}}"#, UInt64(0)),
            (#"{"totalTokens":100000000000000000000e-20,"cost":{"total":0.01}}"#, 1),
        ] {
            let line = piAssistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
            XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event, usage).record.processedTokens, tokens)
        }
    }

    func testMalformedReadValuesMakeARecordMalformed() {
        var parser = PiLogParser()
        for usage in [
            #"{"totalTokens":01,"cost":{"total":0.01}}"#,
            #"{"totalTokens":1,"cost":{"total":00.01}}"#,
            #"{"totalTokens":1,"cost":{"total":1.}}"#,
            #"{"totalTokens":1,"cost":{"total":0.01 "extra":0}}"#,
        ] {
            let line = piAssistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
            XCTAssertThrowsError(try parse(line, with: &parser), usage)
        }
        let tabbedID = piAssistant(id: "re\tply", parentID: nil, model: "model-a", usage: piUsage(input: 1, cost: "0"))
        XCTAssertThrowsError(try parse(tabbedID, with: &parser))
        var invalidUTF8 = Data(
            piAssistant(id: "reply", parentID: nil, model: "model-a", usage: piUsage(input: 1, cost: "0")).utf8
        )
        invalidUTF8.replaceSubrange(invalidUTF8.range(of: Data("reply".utf8))!, with: [0x72, 0xFF])
        XCTAssertThrowsError(try invalidUTF8.withUnsafeBytes { try parser.parse($0) })
    }

    func testTrailingDataMakesARecordMalformed() {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)

        XCTAssertThrowsError(try parse(line + " garbage", with: &parser))
        XCTAssertNotNil(try parse(line + " \t", with: &parser))
    }
}
