import XCTest

@testable import Koogo

final class PiUsageTests: UsageWorkspaceTestCase {
  func testParserUsesLoggedUsageAndNamesTheModel() throws {
    var parser = PiUsageLogParser()
    for record in [PiLog.sessionHeader, PiLog.thinking(id: "high", parentID: nil, level: "high"), PiLog.user] {
      XCTAssertNil(try parser.parse(record))
    }
    let event = try XCTUnwrap(
      try parser.parse(
        PiLog.assistant(
          id: "first",
          parentID: "user",
          model: "model-a",
          usage: PiLog.usage(input: 40, output: 20, cacheRead: 30, cacheWrite: 10, cost: "0.125"),
        )
      )?.event
    )

    XCTAssertEqual(event.record.timestamp, UsageFixture.timestamp)
    XCTAssertEqual(event.record.processedTokens, 100)
    XCTAssertEqual(event.record.cost.usd, Decimal(string: "0.125"))
    XCTAssertEqual(event.record.model, "provider/model-a")
    XCTAssertNil(
      try parser.parse(
        PiLog.assistant(id: "free", parentID: "first", model: "model-a", usage: PiLog.usage(input: 0, cost: "0"))
      )
    )
  }

  func testParserIncludesAuxiliaryUsageWithoutAModel() throws {
    var parser = PiUsageLogParser()
    _ = try parser.parse(PiLog.sessionHeader)
    let records = [
      """
      {"type":"message","id":"tool","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"toolResult","timestamp":1787680800000,"usage":\(PiLog.usage(input: 10, cost: "0.01"))}}
      """,
      """
      {"type":"compaction","id":"compaction","parentId":"tool","timestamp":"2026-08-25T12:00:00.000Z","usage":\(PiLog.usage(input: 20, cost: "0.02"))}
      """,
      """
      {"type":"branch_summary","id":"summary","parentId":"compaction","timestamp":"2026-08-25T12:00:00.000Z","usage":\(PiLog.usage(input: 30, cost: "0.03"))}
      """,
    ]
    let events = try records.map { try XCTUnwrap(parser.parse($0)?.event) }

    XCTAssertEqual(events.map(\.record.processedTokens), [10, 20, 30])
    XCTAssertTrue(events.allSatisfy { $0.record.model == nil })
    XCTAssertEqual(events.map(\.record.cost.usd).reduce(0, +), Decimal(string: "0.06"))
  }

  func testParserBillsUsageEntriesUnderTheirModel() throws {
    var parser = PiUsageLogParser()
    let warm = """
      {"type":"usage","id":"warm","parentId":"first","timestamp":"2026-08-25T12:00:00.000Z","kind":"cache_warm","provider":"provider","model":"model-b","usage":\(PiLog.usage(input: 1, cacheRead: 90, cost: "0.009"))}
      """
    let event = try XCTUnwrap(parser.parse(warm)?.event)

    XCTAssertEqual(event.record.processedTokens, 91)
    XCTAssertEqual(event.record.cost.usd, Decimal(string: "0.009"))
    XCTAssertEqual(event.record.model, "provider/model-b")
  }

  func testParserUsesProviderTotalTokens() throws {
    var parser = PiUsageLogParser()
    let log = """
      {"type":"compaction","id":"compaction","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":40,"totalTokens":125,"cost":{"total":1}}}
      """

    XCTAssertEqual(try XCTUnwrap(parser.parse(log)?.event).record.processedTokens, 125)
  }

  func testCatalogPrefersCustomNamesAndOverridesOverStoredNames() throws {
    try writeModelCatalog()

    var catalog = PiModelCatalog()
    catalog.refresh(home: workspace.home(of: .piAgent))

    let names = ["model-a", "model-b", "unnamed", "unknown"].map {
      catalog.name(of: PiModelCatalog.modelID(provider: "provider", model: $0))
    }
    XCTAssertEqual(names, ["Readable Model A", "Preferred Model B", "unnamed", "unknown"])
  }

  func testPipelineUsesLoggedCostsAndModelNames() async throws {
    try writeModelCatalog()
    let contents = PiLog.session
    try workspace.write(contents, to: workspace.piSessions.appending(path: "project/session.jsonl"))
    try workspace.write(contents, to: workspace.piSessions.appending(path: "copy/session.jsonl"))
    let snapshot = await makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    XCTAssertEqual(snapshot.todayTokens(.piAgent), 210)
    XCTAssertEqual(snapshot.providers[.piAgent]?.periods[.today].total.cost.usd, Decimal(string: "0.21"))
    let models = try XCTUnwrap(snapshot.providers[.piAgent]?.periods[.today].models)
    XCTAssertEqual(
      models.map(\.id),
      [nil, "provider/model-a", "provider/model-b"],
    )
    XCTAssertEqual(models.map(\.modelName), ["Unattributed", "Readable Model A", "Preferred Model B"])
    XCTAssertEqual(models.map(\.usage.processedTokens), [150, 30, 30])
    XCTAssertEqual(
      models.map(\.usage.cost.usd),
      [Decimal(string: "0.15"), Decimal(string: "0.03"), Decimal(string: "0.03")],
    )
  }

  func testPipelineRefreshesModelNamesWhenTheCatalogChanges() async throws {
    try workspace.write(
      PiLog.session,
      to: workspace.piSessions.appending(path: "session.jsonl"),
    )
    try workspace.write(
      """
      {"provider":{"models":[{"id":"model-a","name":"Initial Name"}]}}
      """,
      to: workspace.home(of: .piAgent).appending(path: "models-store.json"),
    )
    let pipeline = makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(initial.providers[.piAgent]?.periods[.today].models?[1].modelName, "Initial Name")

    try workspace.write(
      """
      {"provider":{"models":[{"id":"model-a","name":"Updated Name"}]}}
      """,
      to: workspace.home(of: .piAgent).appending(path: "models-store.json"),
    )
    let updated = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    XCTAssertEqual(updated.providers[.piAgent]?.periods[.today].models?[1].modelName, "Updated Name")
  }

  func testCachedCatalogReflectsMalformedDeletedAndRecreatedFiles() async throws {
    try writeModelCatalog()
    try workspace.write(PiLog.session, to: workspace.piSessions.appending(path: "session.jsonl"))
    let home = workspace.home(of: .piAgent)
    let custom = home.appending(path: "models.json")
    let store = home.appending(path: "models-store.json")
    let pipeline = makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(initial.providers[.piAgent]?.periods[.today].models?[1].modelName, "Readable Model A")

    try workspace.write("{invalid", to: custom)
    let malformed = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(malformed.providers[.piAgent]?.periods[.today].models?[1].modelName, "Cached Model A")

    try FileManager.default.removeItem(at: custom)
    try FileManager.default.removeItem(at: store)
    let deleted = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(deleted.providers[.piAgent]?.periods[.today].models?[1].modelName, "model-a")

    try writeModelCatalog()
    let restored = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(restored, initial)
  }

  func testPipelineDeduplicatesForkHistoryDuringColdAndIncrementalScans() async throws {
    try workspace.write(PiLog.session, to: workspace.piSessions.appending(path: "original.jsonl"))
    let pipeline = makePipeline()

    let original = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    XCTAssertEqual(original.todayTokens(.piAgent), 210)

    let forkHeader = PiLog.sessionHeader.replacing(
      "\"id\":\"session\"",
      with: "\"id\":\"fork\",\"parentSession\":\"original.jsonl\"",
    )
    let fork =
      PiLog.session.replacing(PiLog.sessionHeader, with: forkHeader)
        + PiLog.assistant(
          id: "fork-only",
          parentID: "summary",
          model: "model-a",
          usage: PiLog.usage(input: 70, cost: "0.07"),
        )
        + "\n"
    try workspace.write(fork, to: workspace.piSessions.appending(path: "fork.jsonl"))

    let incremental = try await refresh(pipeline) { $0.ingestion.trackedFiles[.piAgent] == 2 }.snapshot
    let cold = await makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    for snapshot in [incremental, cold] {
      XCTAssertEqual(snapshot.todayTokens(.piAgent), 280)
      XCTAssertEqual(snapshot.providers[.piAgent]?.periods[.today].total.cost.usd, Decimal(string: "0.28"))
    }
  }

  func testPipelineKeepsUnrelatedSessionsThatReuseAnEntryID() async throws {
    let usage = PiLog.usage(input: 10, cost: "0.01")
    try workspace.write(
      PiLog.assistant(id: "shared", parentID: nil, model: "model-a", usage: usage) + "\n",
      to: workspace.piSessions.appending(path: "first.jsonl"),
    )
    try workspace.write(
      PiLog.assistant(
        id: "shared",
        parentID: nil,
        model: "model-a",
        usage: usage,
        requestedAt: UsageFixture.timestamp.addingTimeInterval(-60),
      ) + "\n",
      to: workspace.piSessions.appending(path: "second.jsonl"),
    )

    let snapshot = await makePipeline().run(at: UsageFixture.timestamp, providers: [.piAgent]).snapshot

    XCTAssertEqual(snapshot.todayTokens(.piAgent), 20)
  }

  func testPiRecordsInAnyLayoutPassThroughUntilABilledReply() throws {
    var parser = PiUsageLogParser()
    let records = [
      #"{"type":"session","version":3,"id":"session","timestamp":"2026-08-25T11:00:00.000Z"}"#,
      PiLog.thinking(id: "high", parentID: nil, level: "high"),
      #"{"type":"model_change","id":"model","parentId":"high","timestamp":"2026-08-25T11:40:00.000Z"}"#,
      #"{"id":"reordered","parentId":"model","type":"custom","timestamp":"2026-08-25T11:41:00.000Z"}"#,
      """
      {"type":"message","id":"us\\u0065r","parentId":"reordered","timestamp":"2026-08-25T11:45:00.000Z","message":{"role":"user","content":[]}}
      """,
      """
      {"type":"message","id":"tool","parentId":"user","timestamp":"2026-08-25T11:46:00.000Z","message":{"role":"toolResult","content":[]}}
      """,
    ]
    for record in records {
      XCTAssertNil(try parser.parse(record))
    }

    let event = try XCTUnwrap(
      try parser.parse(
        PiLog.assistant(id: "reply", parentID: "tool", model: "model-a", usage: PiLog.usage(input: 10, cost: "0.01"))
      )?.event
    )

    XCTAssertEqual(event.record.model, "provider/model-a")
  }

  private func writeModelCatalog() throws {
    let piHome = workspace.home(of: .piAgent)
    try workspace.write(
      """
      {"provider":{"models":[{"id":"model-a","name":"Cached Model A"},{"id":"model-b","name":"Model B"},{"id":"unnamed","name":"Stored Name"}]}}
      """,
      to: piHome.appending(path: "models-store.json"),
    )
    try workspace.write(
      """
      \u{FEFF}{
        // pi accepts comments and trailing commas in models.json.
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
      """,
      to: piHome.appending(path: "models.json"),
    )
  }
}

extension PiLog {
  fileprivate static let sessionHeader = """
    {"type":"session","version":3,"id":"session","timestamp":"2026-08-25T11:00:00.000Z","cwd":"/tmp"}
    """

  fileprivate static let user = """
    {"type":"message","id":"user","parentId":"high","timestamp":"2026-08-25T11:45:00.000Z","message":{"role":"user","content":[],"timestamp":1787680700000}}
    """

  fileprivate static var session: String {
    [
      sessionHeader,
      thinking(id: "high", parentID: nil, level: "high"),
      assistant(id: "first", parentID: "high", model: "model-a", usage: usage(input: 10, cost: "0.01")),
      assistant(id: "second", parentID: "first", model: "model-a", usage: usage(input: 20, cost: "0.02")),
      thinking(id: "low", parentID: "second", level: "low"),
      assistant(id: "third", parentID: "low", model: "model-b", usage: usage(input: 30, cost: "0.03")),
      """
      {"type":"message","id":"tool","parentId":"third","timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"toolResult","timestamp":1787680800000,"usage":\(usage(input: 40, cost: "0.04"))}}
      """,
      """
      {"type":"compaction","id":"compaction","parentId":"tool","timestamp":"2026-08-25T12:00:00.000Z","usage":\(usage(input: 50, cost: "0.05"))}
      """,
      """
      {"type":"branch_summary","id":"summary","parentId":"compaction","timestamp":"2026-08-25T12:00:00.000Z","usage":\(usage(input: 60, cost: "0.06"))}
      """,
      "",
    ].joined(separator: "\n")
  }

  fileprivate static func thinking(id: String, parentID: String?, level: String) -> String {
    let parent = parentID.map { "\"\($0)\"" } ?? "null"
    return """
      {"type":"thinking_level_change","id":"\(id)","parentId":\(parent),"timestamp":"2026-08-25T11:30:00.000Z","thinkingLevel":"\(level)"}
      """
  }
}
