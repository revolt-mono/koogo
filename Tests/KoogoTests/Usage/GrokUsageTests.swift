import Foundation
import XCTest

@testable import Koogo

final class GrokUsageTests: UsageWorkspaceTestCase {
    func testParserPricesEveryModelAndFavorsTheMostCalledOne() throws {
        var parser = GrokLogParser()

        let event = try XCTUnwrap(
            parse(
                grokTurn(
                    eventID: "session-1",
                    models: ["grok-4.6-build": GrokModelRow(calls: 10), "grok-4.7-build-fast": GrokModelRow(calls: 6)]
                ),
                with: &parser
            )
        )

        XCTAssertEqual(event.usage.timestamp, usageTestTimestamp)
        XCTAssertEqual(event.usage.processedTokens, 2_200_000)
        XCTAssertEqual(event.usage.costUSD, 6)
        XCTAssertEqual(event.usage.modelTurn?.model, .grok(id: "grok-4.6-build", name: "Grok 4.6"))
        XCTAssertNil(event.usage.modelTurn?.reasoningEffort)
    }

    func testParserIgnoresUpdatesWithoutUsage() {
        var parser = GrokLogParser()
        let lines = [
            """
            {"timestamp":1,"method":"_x.ai/session/update","params":{"sessionId":"session","update":{"sessionUpdate":"turn_completed","prompt_id":"prompt","stop_reason":"cancelled"},"_meta":{"eventId":"session-1","agentTimestampMs":1787680800000}}}
            """,
            """
            {"timestamp":1,"method":"session/update","params":{"sessionId":"session","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"turn_completed usage"}},"_meta":{"eventId":"session-2","agentTimestampMs":1787680800000}}}
            """,
        ]

        for line in lines {
            XCTAssertNil(parse(line, with: &parser))
        }
    }

    func testTurnWithAnUnpricedModelIsReportedWhole() async throws {
        try writeSession(
            "session",
            lines: [
                grokTurn(
                    eventID: "session-1",
                    models: ["grok-4.6-build": GrokModelRow(), "grok-9-build": GrokModelRow()]
                )
            ]
        )

        let report = await UsageService(locations: locations, calendar: calendar).refresh(at: now)

        XCTAssertEqual(report.ingestion.events[.grok], 0)
        XCTAssertEqual(report.ingestion.unpricedModels, ["grok-9-build"])
    }

    func testServiceCountsEachTopLevelTurnOnce() async throws {
        let turn = grokTurn(eventID: "parent-1")
        let parent = try writeSession("parent", lines: [turn])
        // A fork copies earlier turns with their original event id and time.
        try writeSession("fork", kind: "fork", lines: [turn, grokTurn(eventID: "fork-1")])
        // A resumed process can restart the event counter, reusing an id at a later time.
        try writeSession(
            "resumed",
            lines: [
                grokTurn(eventID: "resumed-0", at: now.addingTimeInterval(-60)),
                grokTurn(eventID: "resumed-0"),
            ]
        )
        // The parent turn that spawned a subagent already includes its usage.
        try writeSession("child", kind: "subagent", lines: [grokTurn(eventID: "child-1")])
        try workspace.write(turn + "\n", to: parent.appending(path: "chat_history.jsonl"))
        try workspace.write(
            grokTurn(eventID: "orphan-1") + "\n",
            to: locations.logs.grokSessions.appending(path: "project/orphan/updates.jsonl")
        )

        let report = await UsageService(locations: locations, calendar: calendar).refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles[.grok], 3)
        XCTAssertEqual(report.ingestion.events[.grok], 4)
        let grok = try XCTUnwrap(report.snapshot.providers[.grok])
        XCTAssertEqual(grok.today.processedTokens, 4_400_000)
        XCTAssertEqual(grok.today.costUSD, 8)
        XCTAssertEqual(grok.favorite, ProviderUsageSnapshot.Favorite(modelName: "Grok 4.6", reasoningEffort: nil))
    }

    @discardableResult
    private func writeSession(_ id: String, kind: String? = nil, lines: [String]) throws -> URL {
        let directory = locations.logs.grokSessions.appending(path: "project/\(id)", directoryHint: .isDirectory)
        let kindField = kind.map { ",\"session_kind\":\"\($0)\"" } ?? ""
        try workspace.write(
            "{\"info\":{\"id\":\"\(id)\",\"cwd\":\"/project\"}\(kindField)}",
            to: directory.appending(path: "summary.json")
        )
        try workspace.write(
            lines.map { $0 + "\n" }.joined(),
            to: directory.appending(path: "updates.jsonl")
        )
        return directory
    }
}

/// Priced as `grok-4.6-build`, this row costs $2.00.
private struct GrokModelRow {
    var input = 1_000_000
    var cachedInput = 400_000
    var output = 100_000
    var calls = 10
}

/// Server cost ticks are present but deliberately wrong; pricing must ignore them.
private func grokTurn(
    eventID: String,
    at date: Date = usageTestTimestamp,
    models: [String: GrokModelRow] = ["grok-4.6-build": GrokModelRow()]
) -> String {
    let milliseconds = Int(date.timeIntervalSince1970 * 1_000)
    let totalTokens = models.values.map { $0.input + $0.output }.reduce(0, +)
    let modelUsage = models.map { model, row in
        """
        "\(model)":{"inputTokens":\(row.input),"cachedReadTokens":\(row.cachedInput),"outputTokens":\(row.output),\
        "modelCalls":\(row.calls),"costUsdTicks":1}
        """
    }
    return """
        {"timestamp":1,"method":"_x.ai/session/update","params":{"sessionId":"session","update":{\
        "sessionUpdate":"turn_completed","prompt_id":"prompt","stop_reason":"end_turn","usage":{\
        "totalTokens":\(totalTokens),"costUsdTicks":1,"modelUsage":{\(modelUsage.joined(separator: ","))}}},\
        "_meta":{"eventId":"\(eventID)","agentTimestampMs":\(milliseconds)}}}
        """
}
