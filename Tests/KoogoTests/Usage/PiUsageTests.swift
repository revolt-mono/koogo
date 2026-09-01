import Foundation
import XCTest

@testable import Koogo

final class PiUsageTests: XCTestCase {
    private let decoder = JSONDecoder()
    private var workspace: UsageTestWorkspace!

    private var locations: UsageLocations { workspace.locations }
    private var calendar: Calendar { workspace.calendar }

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    func testParserUsesBranchLocalThinkingAndLoggedUsage() throws {
        var parser = UsageFileParserState.piAgent()
        for record in [piSessionHeader, piThinking(id: "high", parentID: nil, level: "high"), piUser] {
            XCTAssertNil(parse(record, with: &parser))
        }
        let first = try XCTUnwrap(
            parse(
                piAssistant(id: "first", parentID: "user", model: "model-a", cost: "0.125"),
                with: &parser
            )
        )
        XCTAssertNil(parse(piThinking(id: "low", parentID: "high", level: "low"), with: &parser))
        let lowBranch = try XCTUnwrap(
            parse(
                piAssistant(id: "second", parentID: "low", model: "model-b", cost: "0.25"),
                with: &parser
            )
        )
        let highBranch = try XCTUnwrap(
            parse(
                piAssistant(id: "third", parentID: "first", model: "model-a", cost: "0.5"),
                with: &parser
            )
        )

        guard case .piAgent(_, let firstEvent) = first,
            case .piAgent(_, let lowEvent) = lowBranch,
            case .piAgent(_, let highEvent) = highBranch
        else {
            return XCTFail("unexpected event provider")
        }
        XCTAssertEqual(firstEvent.timestamp, usageTestTimestamp)
        XCTAssertEqual(firstEvent.processedTokens, 100)
        XCTAssertEqual(firstEvent.costUSD, Decimal(string: "0.125"))
        XCTAssertEqual(first.usage.modelTurn?.reasoningEffort, "high")
        XCTAssertEqual(lowEvent.modelTurn?.reasoningEffort, "low")
        XCTAssertEqual(highEvent.modelTurn?.reasoningEffort, "high")
    }

    func testParserIncludesAuxiliaryUsageWithoutFavoriteMetadata() throws {
        var parser = UsageFileParserState.piAgent()
        _ = parse(piSessionHeader, with: &parser)
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
        let events = try records.map { try XCTUnwrap(parse($0, with: &parser)) }

        XCTAssertEqual(events.map(\.usage.processedTokens), [10, 20, 30])
        XCTAssertTrue(events.allSatisfy { $0.usage.modelTurn == nil })
        XCTAssertEqual(events.map(\.usage.costUSD).reduce(0, +), Decimal(string: "0.06"))
    }

    func testParserUsesProviderTotalTokens() throws {
        var parser = UsageFileParserState.piAgent()
        let log = """
            {"type":"compaction","id":"compaction","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":40,"totalTokens":125,"cost":{"total":1}}}
            """

        XCTAssertEqual(try XCTUnwrap(parse(log, with: &parser)).usage.processedTokens, 125)
    }

    func testParserKeepsZeroUsageAssistantTurnsForFavorites() throws {
        var parser = UsageFileParserState.piAgent()

        let event = try XCTUnwrap(
            parse(
                """
                {"type":"message","id":"free","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"assistant","provider":"provider","model":"free-model","timestamp":1787680800000,"usage":\(piUsage(input: 0, cost: "0"))}}
                """,
                with: &parser
            )
        )

        XCTAssertEqual(event.usage.processedTokens, 0)
        XCTAssertEqual(
            event.usage.modelTurn?.model,
            .piAgent(provider: "provider", id: "free-model")
        )
        let snapshot = UsageSnapshotBuilder.build(
            events: [event],
            intervals: UsagePeriodIntervals(containing: usageTestTimestamp, calendar: calendar),
            calendar: calendar
        )
        XCTAssertEqual(snapshot.piAgent.month, UsagePeriodSnapshot())
        XCTAssertEqual(
            snapshot.piAgent.favorite,
            ProviderUsageSnapshot.Favorite(modelName: "free-model", reasoningEffort: nil)
        )
    }

    func testServiceUsesLoggedCostsModelNamesAndTurnFavorites() async throws {
        try workspace.write(piModelStore, to: locations.piModels.store)
        try workspace.write(piCustomModels, to: locations.piModels.custom)
        let catalog = PiModelCatalog(locations: locations.piModels)
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "model-a"), "Readable Model A")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "model-b"), "Preferred Model B")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "unnamed"), "unnamed")
        XCTAssertEqual(catalog.displayName(provider: "provider", model: "unknown"), "unknown")

        let contents = piSessionLog
        try workspace.write(contents, to: locations.logs.piAgent.appending(path: "project/session.jsonl"))
        try workspace.write(contents, to: locations.logs.piAgent.appending(path: "copy/session.jsonl"))
        let snapshot = await UsageService(locations: locations, calendar: calendar).refresh(
            at: usageTestTimestamp
        ).snapshot

        XCTAssertEqual(snapshot.piAgent.today.processedTokens, 210)
        XCTAssertEqual(snapshot.piAgent.today.costUSD, Decimal(string: "0.21"))
        XCTAssertEqual(snapshot.summary.today.current.processedTokens, 210)
        XCTAssertEqual(snapshot.summary.today.current.costUSD, Decimal(string: "0.21"))
        XCTAssertEqual(
            snapshot.piAgent.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "Readable Model A",
                reasoningEffort: "high"
            )
        )
    }

    func testServiceRefreshesFavoriteWhenModelCatalogChanges() async throws {
        try workspace.write(
            piSessionLog,
            to: locations.logs.piAgent.appending(path: "session.jsonl")
        )
        try workspace.write(
            """
            {"provider":{"models":[{"id":"model-a","name":"Initial Name"}]}}
            """,
            to: locations.piModels.store
        )
        let service = UsageService(locations: locations, calendar: calendar)
        let initial = await service.refresh(at: usageTestTimestamp).snapshot
        XCTAssertEqual(initial.piAgent.favorite?.modelName, "Initial Name")

        try workspace.write(
            """
            {"provider":{"models":[{"id":"model-a","name":"Updated Name"}]}}
            """,
            to: locations.piModels.store
        )
        let updated = await service.refresh(at: usageTestTimestamp).snapshot

        XCTAssertEqual(updated.piAgent.favorite?.modelName, "Updated Name")
    }

    func testServiceDeduplicatesForkHistoryDuringColdAndIncrementalScans() async throws {
        try workspace.write(piSessionLog, to: locations.logs.piAgent.appending(path: "original.jsonl"))
        let service = UsageService(locations: locations, calendar: calendar)

        let original = await service.refresh(at: usageTestTimestamp).snapshot
        XCTAssertEqual(original.piAgent.today.processedTokens, 210)

        let forkHeader = piSessionHeader.replacingOccurrences(
            of: "\"id\":\"session\"",
            with: "\"id\":\"fork\",\"parentSession\":\"original.jsonl\""
        )
        let fork =
            piSessionLog.replacingOccurrences(of: piSessionHeader, with: forkHeader)
            + piAssistantEntry(
                id: "fork-only",
                parentID: "summary",
                model: "model-a",
                tokens: 70,
                cost: "0.07"
            ) + "\n"
        try workspace.write(fork, to: locations.logs.piAgent.appending(path: "fork.jsonl"))

        let incremental = await service.refresh(at: usageTestTimestamp).snapshot
        let cold = await UsageService(locations: locations, calendar: calendar).refresh(
            at: usageTestTimestamp
        ).snapshot
        for snapshot in [incremental, cold] {
            XCTAssertEqual(snapshot.piAgent.today.processedTokens, 280)
            XCTAssertEqual(snapshot.piAgent.today.costUSD, Decimal(string: "0.28"))
        }
    }

    private func parse(_ line: String, with parser: inout UsageFileParserState) -> UsageEvent? {
        Data(line.utf8).withUnsafeBytes {
            guard case .event(let event)? = parser.parse($0, decoder: decoder) else {
                return nil
            }
            return event
        }
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
        piAssistantEntry(id: "first", parentID: "high", model: "model-a", tokens: 10, cost: "0.01"),
        piAssistantEntry(id: "second", parentID: "first", model: "model-a", tokens: 20, cost: "0.02"),
        piThinking(id: "low", parentID: "second", level: "low"),
        piAssistantEntry(id: "third", parentID: "low", model: "model-b", tokens: 30, cost: "0.03"),
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

private func piAssistant(id: String, parentID: String, model: String, cost: String) -> String {
    """
    {"type":"message","id":"\(id)","parentId":"\(parentID)","timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"assistant","provider":"provider","model":"\(model)","timestamp":1787680800000,"usage":\(piUsage(input: 40, output: 20, cacheRead: 30, cacheWrite: 10, cost: cost))}}
    """
}

private func piAssistantEntry(
    id: String,
    parentID: String,
    model: String,
    tokens: Int,
    cost: String
) -> String {
    """
    {"type":"message","id":"\(id)","parentId":"\(parentID)","timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"assistant","provider":"provider","model":"\(model)","timestamp":1787680800000,"usage":\(piUsage(input: tokens, cost: cost))}}
    """
}

private func piUsage(
    input: Int,
    output: Int = 0,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    cost: String
) -> String {
    """
    {"input":\(input),"output":\(output),"cacheRead":\(cacheRead),"cacheWrite":\(cacheWrite),"totalTokens":\(input + output + cacheRead + cacheWrite),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\(cost)}}
    """
}
