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
        XCTAssertEqual(event.usage.modelTurn?.model, UsageModelReference(id: "grok-4.6-build", name: "Grok 4.6"))
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
            updates: [
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
        let parent = try writeSession("parent", updates: [turn])
        try writeSession("fork", kind: "fork", updates: [turn, grokTurn(eventID: "fork-1")])
        try writeSession(
            "resumed",
            updates: [
                grokTurn(eventID: "resumed-0", at: now.addingTimeInterval(-60)),
                grokTurn(eventID: "resumed-0"),
            ]
        )
        try writeSession("child", kind: "subagent", updates: [grokTurn(eventID: "child-1")])
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

    func testFavoriteUsesHistoricalEffortOncePerPrompt() async throws {
        let history =
            [grokHistoryUser(0)] + Array(repeating: grokAssistant("high"), count: 8)
            + [grokHistoryUser(1), grokAssistant("low"), grokHistoryUser(2), grokAssistant("low")]
        let session = try writeSession(
            "efforts",
            updates: (0..<3).flatMap { [grokUser($0), grokTurn(eventID: "event-\($0)")] },
            history: history
        )
        try workspace.write(
            #"{"current_model_id":"grok-4.6","reasoning_effort":"xhigh"}"#,
            to: session.appending(path: "summary.json")
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertEqual(report.snapshot.providers[.grok]?.favorite?.reasoningEffort, "low")
        XCTAssertEqual(report.ingestion.events[.grok], 3)
        XCTAssertEqual(report.ingestion.malformedLines[.grok], 0)
        XCTAssertEqual(report.snapshot.providers[.grok]?.today.processedTokens, 3_300_000)
        XCTAssertEqual(report.snapshot.providers[.grok]?.today.costUSD, 6)
    }

    func testHistoryChangesRefreshUnchangedUsage() async throws {
        let session = try writeSession("late-history", updates: [grokUser(0), grokTurn(eventID: "event")])
        let historyURL = session.appending(path: "chat_history.jsonl")
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let before = await service.refresh(at: now)
        XCTAssertNil(before.snapshot.providers[.grok]?.favorite?.reasoningEffort)

        try workspace.write(grokHistoryUser(0) + "\n" + grokAssistant("low"), to: historyURL)
        let partial = await service.refresh(at: now)
        XCTAssertNil(partial.snapshot.providers[.grok]?.favorite?.reasoningEffort)
        try workspace.append("\n", to: historyURL)
        let completed = await service.refresh(at: now)
        XCTAssertEqual(completed.snapshot.providers[.grok]?.favorite?.reasoningEffort, "low")

        try workspace.write(
            grokHistoryUser(0) + "\n" + grokAssistant("max") + "\n",
            to: historyURL,
            modificationDate: now.addingTimeInterval(1)
        )
        let replaced = await service.refresh(at: now)
        XCTAssertEqual(replaced.snapshot.providers[.grok]?.favorite?.reasoningEffort, "max")
        XCTAssertEqual(replaced.ingestion.events[.grok], 1)
        XCTAssertEqual(replaced.snapshot.providers[.grok]?.today, before.snapshot.providers[.grok]?.today)

        try FileManager.default.removeItem(at: historyURL)
        let removed = await service.refresh(at: now)
        XCTAssertNil(removed.snapshot.providers[.grok]?.favorite?.reasoningEffort)
        XCTAssertEqual(removed.snapshot.providers[.grok]?.today, before.snapshot.providers[.grok]?.today)
    }

    func testHistoryRequiresMatchingPromptAndPrimaryModel() async throws {
        try writeSession(
            "different-model",
            updates: [
                grokUser(0),
                grokTurn(
                    eventID: "event",
                    models: ["grok-4.6-build": GrokModelRow(calls: 1), "grok-4.7-build-fast": GrokModelRow(calls: 8)]
                ),
            ],
            history: [
                grokAssistant("xhigh", model: "grok-4.7-build-fast"),
                grokHistoryUser(0), grokAssistant("high"),
                grokHistoryUser(1), grokAssistant("low", model: "grok-4.7-build-fast"),
            ]
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertEqual(report.snapshot.providers[.grok]?.favorite?.modelName, "Grok 4.7 Fast")
        XCTAssertNil(report.snapshot.providers[.grok]?.favorite?.reasoningEffort)
        XCTAssertEqual(report.snapshot.providers[.grok]?.today.costUSD, 6)
    }

    func testRewindDoesNotApplyNewEffortToAbandonedTurns() throws {
        let session = try writeSession(
            "rewound",
            updates: [grokUser(0), grokTurn(eventID: "old")],
            history: [grokHistoryUser(0), grokAssistant("low")]
        )
        let historyURL = session.appending(path: "chat_history.jsonl")
        var index = UsageLogIndex(locations: locations)
        _ = index.refresh(since: now.addingTimeInterval(-60), providers: [.grok])
        var initial: [UsageEvent] = []
        _ = index.collect { initial.append($0) }
        XCTAssertEqual(initial.first?.usage.modelTurn?.reasoningEffort, "low")

        try workspace.append(
            [
                #"{"params":{"update":{"sessionUpdate":"rewind_marker","target_prompt_index":0}}}"#,
                grokUser(0), grokTurn(eventID: "new"),
            ].joined(separator: "\n") + "\n",
            to: session.appending(path: "updates.jsonl")
        )
        try workspace.write(grokHistoryUser(0) + "\n" + grokAssistant("high") + "\n", to: historyURL)
        _ = index.refresh(since: now.addingTimeInterval(-60), providers: [.grok])
        var events: [UsageEvent] = []
        let stats = index.collect { events.append($0) }
        let byKey = Dictionary(uniqueKeysWithValues: events.map { ($0.key, $0.usage) })

        XCTAssertNil(byKey[.grok(eventID: "old", timestamp: now)]?.modelTurn?.reasoningEffort)
        XCTAssertEqual(byKey[.grok(eventID: "new", timestamp: now)]?.modelTurn?.reasoningEffort, "high")
        XCTAssertEqual(stats.events[.grok], 2)
    }

    func testAppendedTurnUsesNewHistoryWithoutChangingPreviousEffort() async throws {
        let session = try writeSession(
            "appended",
            updates: [grokUser(0), grokTurn(eventID: "first")],
            history: [grokHistoryUser(0), grokAssistant("low")]
        )
        let historyURL = session.appending(path: "chat_history.jsonl")
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let initial = await service.refresh(at: now)
        XCTAssertEqual(initial.snapshot.providers[.grok]?.favorite?.reasoningEffort, "low")

        try workspace.append(grokHistoryUser(1) + "\n" + grokAssistant("high") + "\n", to: historyURL)
        let pending = await service.refresh(at: now)
        XCTAssertEqual(pending.snapshot.providers[.grok]?.favorite?.reasoningEffort, "low")
        try workspace.append(
            grokUser(1) + "\n" + grokTurn(eventID: "second") + "\n",
            to: session.appending(path: "updates.jsonl")
        )
        let completed = await service.refresh(at: now)
        XCTAssertEqual(completed.snapshot.providers[.grok]?.favorite?.reasoningEffort, "high")
        XCTAssertEqual(completed.ingestion.events[.grok], 2)
        XCTAssertEqual(completed.snapshot.providers[.grok]?.today.costUSD, 4)
    }

    func testMalformedContextAndHistoryAreReportedWithoutDroppingUsage() async throws {
        try writeSession(
            "malformed-history",
            updates: [
                #"{"params":{"update":{"sessionUpdate":"user_message_chunk","_meta":{"promptIndex":"bad"}}}}"#,
                grokUser(0), grokTurn(eventID: "event"),
            ],
            history: [
                grokHistoryUser(0),
                #"{"type":"assistant","model_id":"grok-4.6-build","reasoning_effort":42}"#,
            ]
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertNil(report.snapshot.providers[.grok]?.favorite?.reasoningEffort)
        XCTAssertEqual(report.ingestion.malformedLines[.grok], 2)
        XCTAssertEqual(report.ingestion.events[.grok], 1)
    }

    func testForkDeduplicationKeepsTheCopyWithHistoricalEffort() async throws {
        let updates = [grokUser(0), grokTurn(eventID: "shared-event")]
        try writeSession("a-compacted", updates: updates)
        try writeSession(
            "z-fork",
            kind: "fork",
            updates: updates,
            history: [grokHistoryUser(0), grokAssistant("high")]
        )

        let report = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now)

        XCTAssertEqual(report.snapshot.providers[.grok]?.favorite?.reasoningEffort, "high")
        XCTAssertEqual(report.ingestion.events[.grok], 1)
        XCTAssertEqual(report.snapshot.providers[.grok]?.today.costUSD, 2)
    }

    func testBuildModelsUseFlatStandardRatesAndFastDoublesThem() throws {
        let tokens = try XCTUnwrap(
            GrokTokenUsage(input: 1_000_000, cachedInput: 400_000, output: 100_000, modelCalls: 1)
        )
        let build = try XCTUnwrap(GrokUsagePricing.quote(model: "grok-4.6-build", tokens: tokens))
        let fast = try XCTUnwrap(GrokUsagePricing.quote(model: "grok-4.7-build-fast", tokens: tokens))

        XCTAssertEqual(build.model, UsageModelReference(id: "grok-4.6-build", name: "Grok 4.6"))
        XCTAssertEqual(build.costUSD, 2)
        XCTAssertEqual(GrokUsagePricing.quote(model: "grok-4.6", tokens: tokens)?.costUSD, 2)
        XCTAssertEqual(fast.model, UsageModelReference(id: "grok-4.7-build-fast", name: "Grok 4.7 Fast"))
        XCTAssertEqual(fast.costUSD, 4)
        XCTAssertEqual(
            GrokUsagePricing.quote(model: "grok-4.5-build", tokens: tokens)?.costUSD,
            Decimal(string: "1.92")
        )
        XCTAssertNil(GrokUsagePricing.quote(model: "grok-9-build", tokens: tokens))
        XCTAssertNil(GrokUsagePricing.quote(model: "grok-4.6-fast", tokens: tokens))
    }
}

private extension GrokUsageTests {
    func grokUser(_ index: Int) -> String {
        """
        {"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"hello"},"_meta":{"modelId":"grok-4.6","promptIndex":\(index)}}}}
        """
    }

    func grokHistoryUser(_ index: Int) -> String {
        #"{"type":"user","content":[{"type":"text","text":"hello"}],"prompt_index":\#(index)}"#
    }

    func grokAssistant(_ effort: String, model: String = "grok-4.6-build") -> String {
        #"{"type":"assistant","content":"hello","model_id":"\#(model)","reasoning_effort":"\#(effort)"}"#
    }

    @discardableResult
    func writeSession(_ id: String, kind: String? = nil, updates: [String], history: [String]? = nil) throws -> URL {
        let directory = workspace.grokSessions.appending(path: "project/\(id)", directoryHint: .isDirectory)
        let kindField = kind.map { ",\"session_kind\":\"\($0)\"" } ?? ""
        try workspace.write(
            "{\"info\":{\"id\":\"\(id)\",\"cwd\":\"/project\"}\(kindField)}",
            to: directory.appending(path: "summary.json")
        )
        for (name, lines) in [("updates.jsonl", updates), ("chat_history.jsonl", history)] {
            if let lines {
                try workspace.write(lines.map { $0 + "\n" }.joined(), to: directory.appending(path: name))
            }
        }
        return directory
    }
}
