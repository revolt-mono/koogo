import Foundation
import Testing

@testable import Koogo

struct PiUsageTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `parser uses logged usage and names the model`() throws {
    var parser = PiUsageLogParser()
    for record in [PiLog.sessionHeader, PiLog.thinking(id: "high", parentID: nil, level: "high"), PiLog.user] {
      try #expect(parser.parse(record) == nil)
    }
    let event = try #require(
      parser.parse(
        PiLog.assistant(
          id: "first",
          parentID: "user",
          model: "model-a",
          usage: PiLog.usage(input: 40, output: 20, cacheRead: 30, cacheWrite: 10, cost: "0.125"),
        )
      )?.event
    )

    #expect(event.record.timestamp.date == UsageFixture.timestamp)
    #expect(event.record.processedTokens == 100)
    #expect(event.record.cost.usd == Decimal(string: "0.125"))
    #expect(event.record.model == "provider/model-a")
    let free = PiLog.assistant(id: "free", parentID: "first", model: "model-a", usage: PiLog.usage(input: 0, cost: "0"))
    try #expect(parser.parse(free) == nil)
  }

  @Test
  func `parser includes auxiliary usage without a model`() throws {
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
    let events = try records.map { try #require(parser.parse($0)?.event) }

    #expect(events.map(\.record.processedTokens) == [10, 20, 30])
    #expect(events.allSatisfy { $0.record.model == nil })
    #expect(events.map(\.record.cost.usd).reduce(0, +) == Decimal(string: "0.06"))
  }

  @Test
  func `parser bills usage entries under their model`() throws {
    var parser = PiUsageLogParser()
    let warm = """
      {"type":"usage","id":"warm","parentId":"first","timestamp":"2026-08-25T12:00:00.000Z","kind":"cache_warm","provider":"provider","model":"model-b","usage":\(PiLog.usage(input: 1, cacheRead: 90, cost: "0.009"))}
      """
    let event = try #require(parser.parse(warm)?.event)

    #expect(event.record.processedTokens == 91)
    #expect(event.record.cost.usd == Decimal(string: "0.009"))
    #expect(event.record.model == "provider/model-b")
  }

  @Test
  func `parser uses provider total tokens`() throws {
    var parser = PiUsageLogParser()
    let log = """
      {"type":"compaction","id":"compaction","parentId":null,"timestamp":"2026-08-25T12:00:00.000Z","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":40,"totalTokens":125,"cost":{"total":1}}}
      """

    try #expect(parser.parse(log)?.event?.record.processedTokens == 125)
  }

  @Test
  func `catalog prefers custom names and overrides over stored names`() throws {
    try writeModelCatalog()

    var catalog = PiModelCatalog()
    catalog.refresh(home: workspace.home(of: .piAgent))

    let names = ["model-a", "model-b", "unnamed", "unknown"].map {
      catalog.name(of: PiModelCatalog.modelID(provider: "provider", model: $0))
    }
    #expect(names == ["Readable Model A", "Preferred Model B", "unnamed", "unknown"])
  }

  @Test
  func `pipeline uses logged costs and model names`() async throws {
    try writeModelCatalog()
    let contents = PiLog.session
    try workspace.write(contents, to: workspace.piSessions.appending(path: "project/session.jsonl"))
    try workspace.write(contents, to: workspace.piSessions.appending(path: "copy/session.jsonl"))
    let snapshot = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(snapshot.todayTokens(.piAgent) == 210)
    #expect(snapshot.providers[.piAgent]?.periods[.today].total.cost.usd == Decimal(string: "0.21"))
    let models = try #require(snapshot.providers[.piAgent]?.periods[.today].models)
    #expect(models.map(\.id) == [nil, "provider/model-a", "provider/model-b"])
    #expect(models.map(\.modelName) == ["Unattributed", "Readable Model A", "Preferred Model B"])
    #expect(models.map(\.usage.processedTokens) == [150, 30, 30])
    #expect(models.map(\.usage.cost.usd) == [Decimal(string: "0.15"), Decimal(string: "0.03"), Decimal(string: "0.03")])
  }

  @Test
  func `pipeline refreshes model names when the catalog changes`() async throws {
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
    let pipeline = workspace.makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(initial.providers[.piAgent]?.periods[.today].models?[1].modelName == "Initial Name")

    try workspace.write(
      """
      {"provider":{"models":[{"id":"model-a","name":"Updated Name"}]}}
      """,
      to: workspace.home(of: .piAgent).appending(path: "models-store.json"),
    )
    let updated = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot

    #expect(updated.providers[.piAgent]?.periods[.today].models?[1].modelName == "Updated Name")
  }

  @Test
  func `cached catalog reflects malformed deleted and recreated files`() async throws {
    try writeModelCatalog()
    try workspace.write(PiLog.session, to: workspace.piSessions.appending(path: "session.jsonl"))
    let home = workspace.home(of: .piAgent)
    let custom = home.appending(path: "models.json")
    let store = home.appending(path: "models-store.json")
    let pipeline = workspace.makePipeline()
    let initial = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(initial.providers[.piAgent]?.periods[.today].models?[1].modelName == "Readable Model A")

    try workspace.write("{invalid", to: custom)
    let malformed = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(malformed.providers[.piAgent]?.periods[.today].models?[1].modelName == "Cached Model A")

    try FileManager.default.removeItem(at: custom)
    try FileManager.default.removeItem(at: store)
    let deleted = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(deleted.providers[.piAgent]?.periods[.today].models?[1].modelName == "model-a")

    try writeModelCatalog()
    let restored = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(restored == initial)
  }

  @Test
  func `pipeline deduplicates fork history during cold and incremental scans`() async throws {
    try workspace.write(PiLog.session, to: workspace.piSessions.appending(path: "original.jsonl"))
    let pipeline = workspace.makePipeline()

    let original = await pipeline.run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    #expect(original.todayTokens(.piAgent) == 210)

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

    let incremental = try await workspace.refresh(pipeline) { $0.ingestion.trackedFiles[.piAgent] == 2 }.snapshot
    let cold = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: Provider.allCases).snapshot
    for snapshot in [incremental, cold] {
      #expect(snapshot.todayTokens(.piAgent) == 280)
      #expect(snapshot.providers[.piAgent]?.periods[.today].total.cost.usd == Decimal(string: "0.28"))
    }
  }

  @Test
  func `pipeline keeps unrelated sessions that reuse an entry id`() async throws {
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

    let snapshot = await workspace.makePipeline().run(at: UsageFixture.timestamp, providers: [.piAgent]).snapshot

    #expect(snapshot.todayTokens(.piAgent) == 20)
  }

  @Test
  func `pi records in any layout pass through until a billed reply`() throws {
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
      try #expect(parser.parse(record) == nil)
    }

    let event = try #require(
      parser.parse(
        PiLog.assistant(id: "reply", parentID: "tool", model: "model-a", usage: PiLog.usage(input: 10, cost: "0.01"))
      )?.event
    )

    #expect(event.record.model == "provider/model-a")
  }

  @Test
  func `pi skips unbilled entries without reading their timestamps`() throws {
    var parser = PiUsageLogParser()
    for line in [
      #"{"type":"thinking_level_change","id":"high","parentId":null,"timestamp":1,"thinkingLevel":"high"}"#,
      #"{"type":"compaction","id":"compaction","parentId":"high","timestamp":1,"summary":""}"#,
    ] {
      try #expect(parser.parse(line) == nil, "\(line)")
    }
  }

  private let workspace: UsageTestWorkspace

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
