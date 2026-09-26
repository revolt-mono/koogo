import Foundation
import XCTest

@testable import Koogo

final class PiUsageTests: UsageWorkspaceTestCase {
    func testParserUsesBranchLocalThinkingAndLoggedUsage() throws {
        var parser = PiLogParser()
        for record in [piSessionHeader, piThinking(id: "high", parentID: nil, level: "high"), piUser] {
            XCTAssertNil(try parse(record, with: &parser))
        }
        let usage = { (cost: String) in piUsage(input: 40, output: 20, cacheRead: 30, cacheWrite: 10, cost: cost) }
        let first = try XCTUnwrap(
            try parse(
                piAssistant(id: "first", parentID: "user", model: "model-a", usage: usage("0.125")),
                with: &parser
            )?.event
        )
        XCTAssertNil(try parse(piThinking(id: "low", parentID: "high", level: "low"), with: &parser))
        let lowBranch = try XCTUnwrap(
            try parse(
                piAssistant(id: "second", parentID: "low", model: "model-b", usage: usage("0.25")),
                with: &parser
            )?.event
        )
        let highBranch = try XCTUnwrap(
            try parse(
                piAssistant(id: "third", parentID: "first", model: "model-a", usage: usage("0.5")),
                with: &parser
            )?.event
        )

        XCTAssertEqual(first.usage.timestamp, usageTestTimestamp)
        XCTAssertEqual(first.usage.processedTokens, 100)
        XCTAssertEqual(first.usage.costUSD, Decimal(string: "0.125"))
        XCTAssertEqual(first.usage.modelTurn?.reasoningEffort, "high")
        XCTAssertEqual(lowBranch.usage.modelTurn?.reasoningEffort, "low")
        XCTAssertEqual(highBranch.usage.modelTurn?.reasoningEffort, "high")
    }

    func testParserIncludesAuxiliaryUsageWithoutFavoriteMetadata() throws {
        var parser = PiLogParser()
        _ = try parse(piSessionHeader, with: &parser)
        let records = [
            """
            {"type":"message","id":"tool","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"toolResult","timestamp":1787680800000,"usage":\(piUsage(input: 10, cost: "0.01"))}}
            """,
            """
            {"type":"compaction","id":"compaction","parentId":"tool","timestamp":"2026-08-25T12:00:00.000Z","usage":\(piUsage(input: 20, cost: "0.02"))}
            """,
            """
            {"type":"branch_summary","id":"summary","parentId":"compaction","timestamp":"2026-08-25T12:00:00.000Z","usage":\(piUsage(input: 30, cost: "0.03"))}
            """,
        ]
        let events = try records.map { try XCTUnwrap(try parse($0, with: &parser)?.event) }

        XCTAssertEqual(events.map(\.usage.processedTokens), [10, 20, 30])
        XCTAssertTrue(events.allSatisfy { $0.usage.modelTurn == nil })
        XCTAssertEqual(events.map(\.usage.costUSD).reduce(0, +), Decimal(string: "0.06"))
    }

    func testParserUsesProviderTotalTokens() throws {
        var parser = PiLogParser()
        let log = """
            {"type":"compaction","id":"compaction","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":40,"totalTokens":125,"cost":{"total":1}}}
            """

        XCTAssertEqual(try XCTUnwrap(try parse(log, with: &parser)?.event).usage.processedTokens, 125)
    }

    func testParserKeepsZeroUsageAssistantTurnsForFavorites() throws {
        var parser = PiLogParser()

        let event = try XCTUnwrap(
            try parse(
                piAssistant(id: "free", parentID: nil, model: "free-model", usage: piUsage(input: 0, cost: "0")),
                with: &parser
            )?.event
        )

        XCTAssertEqual(event.usage.processedTokens, 0)
        XCTAssertEqual(
            event.usage.modelTurn?.model,
            .piAgent(provider: "provider", id: "free-model")
        )
        let snapshot = UsageSnapshotBuilder.build(
            events: [event],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: usageTestCalendar)
        )
        XCTAssertEqual(snapshot.providers[.piAgent]?.month, UsagePeriodSnapshot())
        XCTAssertEqual(
            snapshot.providers[.piAgent]?.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "free-model", reasoningEffort: nil)
        )
    }

    func testCatalogPrefersCustomNamesAndOverridesOverStoredNames() throws {
        try writeModelCatalog()

        let catalog = PiModelCatalog(home: locations.home(of: .piAgent))

        XCTAssertEqual(catalog.displayName(provider: "provider", model: "model-a"), "Readable Model A")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "model-b"), "Preferred Model B")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "unnamed"), "unnamed")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "unknown"), "unknown")
    }

    func testServiceUsesLoggedCostsModelNamesAndTurnFavorites() async throws {
        try writeModelCatalog()
        let contents = piSessionLog
        try workspace.write(contents, to: workspace.piSessions.appending(path: "project/session.jsonl"))
        try workspace.write(contents, to: workspace.piSessions.appending(path: "copy/session.jsonl"))
        let snapshot = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot

        XCTAssertEqual(snapshot.providers[.piAgent]?.today.processedTokens, 210)
        XCTAssertEqual(snapshot.providers[.piAgent]?.today.costUSD, Decimal(string: "0.21"))
        XCTAssertEqual(
            snapshot.providers[.piAgent]?.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "Readable Model A",
                reasoningEffort: "high"
            )
        )
    }

    func testServiceRefreshesFavoriteWhenModelCatalogChanges() async throws {
        try workspace.write(
            piSessionLog,
            to: workspace.piSessions.appending(path: "session.jsonl")
        )
        try workspace.write(
            """
            {"provider":{"models":[{"id":"model-a","name":"Initial Name"}]}}
            """,
            to: locations.home(of: .piAgent).appending(path: "models-store.json")
        )
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let initial = await service.refresh(at: now).snapshot
        XCTAssertEqual(initial.providers[.piAgent]?.favorite?.modelName, "Initial Name")

        try workspace.write(
            """
            {"provider":{"models":[{"id":"model-a","name":"Updated Name"}]}}
            """,
            to: locations.home(of: .piAgent).appending(path: "models-store.json")
        )
        let updated = await service.refresh(at: now).snapshot

        XCTAssertEqual(updated.providers[.piAgent]?.favorite?.modelName, "Updated Name")
    }

    func testServiceDeduplicatesForkHistoryDuringColdAndIncrementalScans() async throws {
        try workspace.write(piSessionLog, to: workspace.piSessions.appending(path: "original.jsonl"))
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let original = await service.refresh(at: now).snapshot
        XCTAssertEqual(original.providers[.piAgent]?.today.processedTokens, 210)

        let forkHeader = piSessionHeader.replacingOccurrences(
            of: "\"id\":\"session\"",
            with: "\"id\":\"fork\",\"parentSession\":\"original.jsonl\""
        )
        let fork =
            piSessionLog.replacingOccurrences(of: piSessionHeader, with: forkHeader)
            + piAssistant(
                id: "fork-only",
                parentID: "summary",
                model: "model-a",
                usage: piUsage(input: 70, cost: "0.07")
            )
            + "\n"
        try workspace.write(fork, to: workspace.piSessions.appending(path: "fork.jsonl"))

        let incremental = await service.refresh(at: now).snapshot
        let cold = await UsageService(locations: locations, calendar: usageTestCalendar).refresh(at: now).snapshot
        for snapshot in [incremental, cold] {
            XCTAssertEqual(snapshot.providers[.piAgent]?.today.processedTokens, 280)
            XCTAssertEqual(snapshot.providers[.piAgent]?.today.costUSD, Decimal(string: "0.28"))
        }
    }

    private func writeModelCatalog() throws {
        let piHome = locations.home(of: .piAgent)
        try workspace.write(piModelStore, to: piHome.appending(path: "models-store.json"))
        try workspace.write(piCustomModels, to: piHome.appending(path: "models.json"))
    }
}

private let piSessionHeader = """
    {"type":"session","version":3,"id":"session","timestamp":"2026-08-25T11:00:00.000Z","cwd":"/tmp"}
    """

private let piUser = """
    {"type":"message","id":"user","parentId":"high","timestamp":"2026-08-25T11:45:00.000Z","message":{"role":"user","content":[],"timestamp":1787680700000}}
    """

private let piModelStore = """
    {"provider":{"models":[{"id":"model-a","name":"Cached Model A"},{"id":"model-b","name":"Model B"},{"id":"unnamed","name":"Stored Name"}]}}
    """

private let piCustomModels = """
    \u{FEFF}{
      // Pi accepts comments and trailing commas in models.json.
      "providers": {
        "provider": {
          "apiKey": "ignored",
          "models": [
            {"id": "model-a", "name": "Readable Model A"},
            {"id": "unnamed"},
          ],
          "modelOverrides": {
            "model-b": {"name": "Preferred Model B"},
          },
        },
      },
    }
    """

private var piSessionLog: String {
    [
        piSessionHeader,
        piThinking(id: "high", parentID: nil, level: "high"),
        piAssistant(id: "first", parentID: "high", model: "model-a", usage: piUsage(input: 10, cost: "0.01")),
        piAssistant(id: "second", parentID: "first", model: "model-a", usage: piUsage(input: 20, cost: "0.02")),
        piThinking(id: "low", parentID: "second", level: "low"),
        piAssistant(id: "third", parentID: "low", model: "model-b", usage: piUsage(input: 30, cost: "0.03")),
        """
        {"type":"message","id":"tool","parentId":"third","timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"toolResult","timestamp":1787680800000,"usage":\(piUsage(input: 40, cost: "0.04"))}}
        """,
        """
        {"type":"compaction","id":"compaction","parentId":"tool","timestamp":"2026-08-25T12:00:00.000Z","usage":\(piUsage(input: 50, cost: "0.05"))}
        """,
        """
        {"type":"branch_summary","id":"summary","parentId":"compaction","timestamp":"2026-08-25T12:00:00.000Z","usage":\(piUsage(input: 60, cost: "0.06"))}
        """,
        "",
    ].joined(separator: "\n")
}

private func piThinking(id: String, parentID: String?, level: String) -> String {
    let parent = parentID.map { "\"\($0)\"" } ?? "null"
    return """
        {"type":"thinking_level_change","id":"\(id)","parentId":\(parent),"timestamp":"2026-08-25T11:30:00.000Z","thinkingLevel":"\(level)"}
        """
}
