import Foundation
import XCTest

@testable import Koogo

final class GrokUsageTests: UsageWorkspaceTestCase {
    func testParserPricesEveryModelAndFavorsTheMostCalledOne() throws {
        var parser = GrokLogParser()

        let event = try XCTUnwrap(
            try parse(
                grokTurn(
                    eventID: "session-1",
                    models: ["grok-4.6-build": GrokModelRow(calls: 10), "grok-4.7-build-fast": GrokModelRow(calls: 6)]
                ),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.usage.timestamp, usageTestTimestamp)
        XCTAssertEqual(event.usage.processedTokens, 2_200_000)
        XCTAssertEqual(event.usage.costUSD, 6)
        XCTAssertEqual(event.usage.modelTurn?.model, .named(id: "grok-4.6-build", name: "Grok 4.6"))
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
            XCTAssertNil(try parse(line, with: &parser))
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

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

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
            to: workspace.grokSessions.appending(path: "project/orphan/updates.jsonl")
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertEqual(report.ingestion.trackedFiles[.grok], 3)
        XCTAssertEqual(report.ingestion.events[.grok], 4)
        let grok = try XCTUnwrap(report.snapshot.providers[.grok])
        XCTAssertEqual(grok.today.processedTokens, 4_400_000)
        XCTAssertEqual(grok.today.costUSD, 8)
        XCTAssertEqual(grok.favorite, ProviderUsageSnapshot.Favorite(modelName: "Grok 4.6", reasoningEffort: nil))
    }

    func testSessionIsCountedOnceItsSummaryAppears() async throws {
        let session = workspace.grokSessions.appending(path: "project/late", directoryHint: .isDirectory)
        try workspace.write(grokTurn(eventID: "late-1") + "\n", to: session.appending(path: "updates.jsonl"))
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let before = await service.refresh(at: now)
        XCTAssertEqual(before.ingestion.events[.grok], 0)

        try workspace.write(
            "{\"info\":{\"id\":\"late\",\"cwd\":\"/project\"}}",
            to: session.appending(path: "summary.json")
        )
        let after = await service.refresh(at: now)
        XCTAssertEqual(after.ingestion.events[.grok], 1)
    }

    func testBuildModelsUseFlatStandardRatesAndFastDoublesThem() throws {
        // One call with a 1M-token prompt still bills at standard rates.
        let tokens = try XCTUnwrap(
            GrokTokenUsage(input: 1_000_000, cachedInput: 400_000, output: 100_000, modelCalls: 1)
        )
        let build = try XCTUnwrap(GrokUsagePricing.quote(model: "grok-4.6-build", tokens: tokens))
        let fast = try XCTUnwrap(GrokUsagePricing.quote(model: "grok-4.7-build-fast", tokens: tokens))

        XCTAssertEqual(build.model, .named(id: "grok-4.6-build", name: "Grok 4.6"))
        XCTAssertEqual(build.costUSD, 2)
        XCTAssertEqual(GrokUsagePricing.quote(model: "grok-4.6", tokens: tokens)?.costUSD, 2)
        XCTAssertEqual(fast.model, .named(id: "grok-4.7-build-fast", name: "Grok 4.7 Fast"))
        XCTAssertEqual(fast.costUSD, 4)
        XCTAssertEqual(
            GrokUsagePricing.quote(model: "grok-4.5-build", tokens: tokens)?.costUSD,
            Decimal(string: "1.92")
        )
        XCTAssertNil(GrokUsagePricing.quote(model: "grok-9-build", tokens: tokens))
        XCTAssertNil(GrokUsagePricing.quote(model: "grok-4.6-fast", tokens: tokens))
    }

    @discardableResult
    private func writeSession(_ id: String, kind: String? = nil, lines: [String]) throws -> URL {
        let directory = workspace.grokSessions.appending(path: "project/\(id)", directoryHint: .isDirectory)
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
