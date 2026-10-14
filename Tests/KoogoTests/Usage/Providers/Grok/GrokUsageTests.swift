import Foundation
import XCTest

@testable import Koogo

final class GrokUsageTests: UsageWorkspaceTestCase {
    func testParserPricesEveryModelAndBillsUnderTheMostCalledOne() throws {
        var parser = GrokUsageLogParser()

        let event = try XCTUnwrap(
            try parse(
                grokTurn(
                    eventID: "session-1",
                    models: ["grok-4.6-build": GrokModelRow(calls: 10), "grok-4.7-build-fast": GrokModelRow(calls: 6)]
                ),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.record.timestamp, usageTestTimestamp)
        XCTAssertEqual(event.record.processedTokens, 2_200_000)
        XCTAssertEqual(event.record.cost.usd, 6)
        XCTAssertEqual(event.record.model, ModelID("grok-4.6-build"))
        XCTAssertEqual(GrokUsagePricing.displayName(of: ModelID("grok-4.6-build")), "Grok 4.6")
    }

    func testParserIgnoresUpdatesWithoutUsage() {
        var parser = GrokUsageLogParser()
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
            updates: [
                grokTurn(
                    eventID: "session-1",
                    models: ["grok-4.6-build": GrokModelRow(), "grok-9-build": GrokModelRow()]
                )
            ]
        )

        let report = await makePipeline().run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.events[.grok], 0)
        XCTAssertEqual(report.ingestion.unpricedModels, ["grok-9-build"])
    }

    func testServiceCountsEachTopLevelTurnOnce() async throws {
        let turn = grokTurn(eventID: "parent-1")
        try writeSession("parent", updates: [turn])
        try writeSession("fork", kind: "fork", updates: [turn, grokTurn(eventID: "fork-1")])
        try writeSession(
            "resumed",
            updates: [
                grokTurn(eventID: "resumed-0", at: now.addingTimeInterval(-60)),
                grokTurn(eventID: "resumed-0"),
            ]
        )
        try writeSession("child", kind: "subagent", updates: [grokTurn(eventID: "child-1")])
        try workspace.write(
            grokTurn(eventID: "orphan-1") + "\n",
            to: workspace.grokSessions.appending(path: "project/orphan/updates.jsonl")
        )

        let report = await makePipeline().run(at: now, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.grok], 3)
        XCTAssertEqual(report.ingestion.events[.grok], 4)
        let grok = try XCTUnwrap(report.snapshot.providers[.grok])
        XCTAssertEqual(grok.periods[.today].total.processedTokens, 4_400_000)
        XCTAssertEqual(grok.periods[.today].total.cost.usd, 8)
    }

    func testSessionIsCountedOnceItsSummaryAppears() async throws {
        let session = workspace.grokSessions.appending(path: "project/late", directoryHint: .isDirectory)
        try workspace.write(grokTurn(eventID: "late-1") + "\n", to: session.appending(path: "updates.jsonl"))
        let service = makePipeline()

        let before = await service.run(at: now, providers: Provider.allCases)
        XCTAssertEqual(before.ingestion.events[.grok], 0)

        try workspace.write(
            "{\"info\":{\"id\":\"late\",\"cwd\":\"/project\"}}",
            to: session.appending(path: "summary.json")
        )
        let after = try await refresh(service) { $0.ingestion.events[.grok] != 0 }
        XCTAssertEqual(after.ingestion.events[.grok], 1)
    }

    func testBuildModelsUseFlatStandardRatesAndFastDoublesThem() throws {
        let tokens = try XCTUnwrap(
            GrokTokenUsage(input: 1_000_000, cachedInput: 400_000, output: 100_000, modelCalls: 1)
        )
        func usd(_ model: ModelID) -> Decimal? {
            GrokUsagePricing.cost(of: tokens, model: model)?.usd
        }

        XCTAssertEqual(usd("grok-4.6-build"), 2)
        XCTAssertEqual(usd("grok-4.6"), 2)
        XCTAssertEqual(usd("grok-4.7-build-fast"), 4)
        XCTAssertEqual(GrokUsagePricing.displayName(of: "grok-4.7-build-fast"), "Grok 4.7 Fast")
        XCTAssertEqual(usd("grok-4.5-build"), Decimal(string: "1.92"))
        XCTAssertNil(usd("grok-9-build"))
        XCTAssertNil(usd("grok-4.6-fast"))
    }
}

private extension GrokUsageTests {
    func writeSession(_ id: String, kind: String? = nil, updates: [String]) throws {
        let directory = workspace.grokSessions.appending(path: "project/\(id)", directoryHint: .isDirectory)
        let kindField = kind.map { ",\"session_kind\":\"\($0)\"" } ?? ""
        try workspace.write(
            "{\"info\":{\"id\":\"\(id)\",\"cwd\":\"/project\"}\(kindField)}",
            to: directory.appending(path: "summary.json")
        )
        try workspace.write(updates.map { $0 + "\n" }.joined(), to: directory.appending(path: "updates.jsonl"))
    }
}
