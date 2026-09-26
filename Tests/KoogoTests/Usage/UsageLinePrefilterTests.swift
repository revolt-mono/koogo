import Foundation
import XCTest

@testable import Koogo

/// Parsers rule lines out from their bytes before decoding them; these pin both halves of that deal.
final class UsageLinePrefilterTests: UsageWorkspaceTestCase {
    /// A ratchet: decoding dominates ingestion, so only records that can bill or carry billing context
    /// may reach the JSON decoder.
    func testOnlyBillingRecordsAreDecoded() async throws {
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

        XCTAssertEqual(report.ingestion.decodedLines, [.codex: 2, .claude: 1, .piAgent: 3, .grok: 0])
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
