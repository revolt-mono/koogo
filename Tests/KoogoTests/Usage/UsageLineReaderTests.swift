import Foundation
import XCTest

@testable import Koogo

/// Parsers read a line's members in place, whatever their order, and skip every value they do not bill from.
final class UsageLineReaderTests: UsageWorkspaceTestCase {
    func testRecordsBesideBilledOnesAreSkipped() async throws {
        let request = codexUsage(input: 100, output: 20)
        try workspace.write(
            [
                codexMeta(),
                """
                {"timestamp":"2026-08-25T11:31:00.000Z","ordinal":2,"type":"response_item","payload":{"type":"function_call","name":"token_count"}}
                """,
                """
                {"timestamp":"2026-08-25T11:32:00.000Z","ordinal":3,"type":"event_msg","payload":{"type":"item_completed","item":{}}}
                """,
                codexTurn(),
                codexTokenCount(last: request, total: request),
                "",
            ].joined(separator: "\n"),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        try workspace.write(
            [
                """
                {"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":"assistant usage"}}
                """,
                #"{"parentUuid":"u","isSidechain":false,"attachment":{"type":"file"},"type":"attachment"}"#,
                claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":40"#),
                "",
            ].joined(separator: "\n"),
            to: workspace.claudeProjects.appending(path: "project/session.jsonl")
        )
        try workspace.write(
            [
                #"{"type":"session","version":3,"id":"session","timestamp":"2026-08-25T11:00:00.000Z"}"#,
                piHighThinking,
                #"{"type":"model_change","id":"model","parentId":"high","timestamp":"2026-08-25T11:31:00.000Z"}"#,
                """
                {"type":"message","id":"user","parentId":"model","timestamp":"2026-08-25T11:32:00.000Z","message":{"role":"user","content":[]}}
                """,
                """
                {"type":"message","id":"tool","parentId":"user","timestamp":"2026-08-25T11:33:00.000Z","message":{"role":"toolResult","content":[]}}
                """,
                piAssistant(id: "reply", parentID: "tool", model: "model-a", usage: piUsage(input: 10, cost: "0.01")),
                "",
            ].joined(separator: "\n"),
            to: workspace.piSessions.appending(path: "session.jsonl")
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertEqual(report.ingestion.malformedLines, [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.events, [.codex: 1, .claude: 1, .piAgent: 1, .grok: 0])
        XCTAssertEqual(report.snapshot.providers[.piAgent]?.favorite?.reasoningEffort, "high")
    }

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

        XCTAssertEqual(event.usage.processedTokens, 120)
        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "high")
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

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).usage.processedTokens, 15)
    }

    func testEscapedKeysAndRecordKindsMatchDecodedText() throws {
        var parser = ClaudeLogParser()
        let line = claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":5"#)
            .replacingOccurrences(of: #""type":"assistant""#, with: #""ty\u0070e":"ass\u0069stant""#)
            .replacingOccurrences(of: #""input_tokens""#, with: #""input_\u0074okens""#)

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).usage.processedTokens, 15)
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

        XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event).usage.processedTokens, 15)
    }

    func testIntegersInUnusualFormsAreReadAsJSON() throws {
        var parser = PiLogParser()
        for (usage, tokens) in [
            (#"{"totalTokens":-0,"cost":{"total":0.01}}"#, UInt64(0)),
            (#"{"totalTokens":100000000000000000000e-20,"cost":{"total":0.01}}"#, 1),
        ] {
            let line = piAssistant(id: "reply", parentID: nil, model: "model-a", usage: usage)
            XCTAssertEqual(try XCTUnwrap(try parse(line, with: &parser)?.event, usage).usage.processedTokens, tokens)
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

    func testPiThinkingPassesThroughRecordsInAnyLayout() throws {
        var parser = PiLogParser()
        let records = [
            piHighThinking,
            #"{"type":"model_change","id":"model","parentId":"high","timestamp":"2026-08-25T11:40:00.000Z"}"#,
            #"{"id":"reordered","parentId":"model","type":"custom","timestamp":"2026-08-25T11:41:00.000Z"}"#,
            """
            {"type":"message","id":"us\\u0065r","parentId":"reordered","timestamp":"2026-08-25T11:45:00.000Z","message":{"role":"user","content":[]}}
            """,
        ]
        for record in records {
            XCTAssertNil(try parse(record, with: &parser))
        }

        let event = try XCTUnwrap(
            try parse(
                piAssistant(id: "reply", parentID: "user", model: "model-a", usage: piUsage(input: 10, cost: "0.01")),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.usage.modelTurn?.reasoningEffort, "high")
    }
}

private let piHighThinking = """
    {"type":"thinking_level_change","id":"high","parentId":null,"timestamp":"2026-08-25T11:30:00.000Z","thinkingLevel":"high"}
    """
