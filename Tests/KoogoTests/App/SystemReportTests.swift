import Foundation
import Testing

@testable import Koogo

struct SystemReportTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `report describes usage pipeline and quota outcome`() async throws {
    let quotaWorkspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())

    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )

    let missingExecutables = QuotaSources.missingExecutables
    let data = try await SystemReport.generate(
      pipeline: workspace.makePipeline(),
      quotaSources: QuotaSources(
        codex: CodexQuotaSource(tool: CommandLineTool(candidates: [try quotaWorkspace.makeAppServer()])),
        claude: missingExecutables.claude,
        grok: missingExecutables.grok,
      ),
      at: UsageFixture.timestamp,
    )
    let report = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(report["generatedAt"] as? String == "2026-08-25T18:00:00Z")
    let usage = try #require(report["usage"] as? [String: Any])
    let ingestion = try #require(usage["ingestion"] as? [String: Any])
    #expect(ingestion["trackedFiles"] as? [String: Int] == ["codex": 1, "claude": 0, "piAgent": 0, "grok": 0])
    #expect(ingestion["events"] as? [String: Int] == ["codex": 1, "claude": 0, "piAgent": 0, "grok": 0])
    #expect(ingestion["unpricedModels"] as? [String] == [])
    let logRoots = try #require(ingestion["logRoots"] as? [[String: Any]])
    #expect(logRoots.count == 5)
    #expect(logRoots.allSatisfy { $0["exists"] as? Bool == true })

    let quota = try #require(report["quota"] as? [String: Any])
    let codex = try #require(quota["codex"] as? [String: Any])
    #expect(codex["state"] as? String == "available")
    for provider in ["claude", "grok"] {
      let status = try #require(quota[provider] as? [String: Any], "\(provider)")
      #expect(status["state"] as? String == "unavailable", "\(provider)")
      #expect(status["reason"] as? String == "binaryNotFound", "\(provider)")
      #expect(status["snapshot"] == nil, "\(provider)")
    }
  }

  @Test(arguments: [ProviderUpstreamAccess.Denial.restrictedRegion, .unknownRegion])
  func `a region change stops every report provider and rejects a reset before launch`(
    denial: ProviderUpstreamAccess.Denial
  ) async throws {
    let cli = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let region = cli.root.appending(path: "region.json")
    let access = ProviderUpstreamAccess { try ProviderUpstreamAccess.response(String(contentsOf: region, encoding: .utf8)) }
    let tool = try CommandLineTool(candidates: [cli.makeAppServer()], access: access)
    let sources = QuotaSources(
      codex: CodexQuotaSource(tool: tool),
      claude: ClaudeQuotaSource(tool: tool),
      grok: GrokQuotaSource(tool: tool),
    )

    try #"{"country":"SG"}"#.write(to: region, atomically: true, encoding: .utf8)
    let snapshot = try await sources.codex.load().get()
    let credit = try #require(snapshot.resetCredits?.credits?.first)
    try FileManager.default.removeItem(at: cli.argumentsFile)
    switch denial {
    case .restrictedRegion: try #"{"country":"CN"}"#.write(to: region, atomically: true, encoding: .utf8)
    case .unknownRegion: try FileManager.default.removeItem(at: region)
    }

    let result = await sources.codex.consume(CodexQuotaResetAttempt(credit: credit))
    #expect(result == .failure(.rejected(.upstreamDenied(denial))))
    let data = try await SystemReport.generate(
      pipeline: workspace.makePipeline(),
      quotaSources: sources,
      at: UsageFixture.timestamp,
    )
    let report = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let quota = try #require(report["quota"] as? [String: [String: String]])
    let paused = ["state": "paused", "reason": denial.rawValue]
    #expect(quota == ["codex": paused, "claude": paused, "grok": paused])
    #expect(!FileManager.default.fileExists(atPath: cli.argumentsFile.path))

    try #"{"country":"SG"}"#.write(to: region, atomically: true, encoding: .utf8)
    #expect(await sources.codex.load() == .available(snapshot))
  }

  @Test
  func `report key paths are stable`() async throws {
    let quotaWorkspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())

    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    try workspace.write(ClaudeLog.session(output: 40), to: workspace.claudeProjects.appending(path: "project/main.jsonl"))
    try workspace.write(
      PiLog.assistant(id: "assistant", parentID: nil, model: "model-a", usage: PiLog.usage(input: 100, cost: "0.1"))
        + "\n",
      to: workspace.piSessions.appending(path: "session.jsonl"),
    )
    let grokSession = workspace.grokSessions.appending(path: "project/s", directoryHint: .isDirectory)
    try workspace.write("{}", to: grokSession.appending(path: "summary.json"))
    try workspace.write(GrokLog.turn(eventID: "s-1") + "\n", to: grokSession.appending(path: "updates.jsonl"))

    let codexExecutable = try quotaWorkspace.makeAppServer(quotaResponse: Self.codexQuotaResponse)
    let claudeExecutable = try ClaudeQuotaTestWorkspace(root: scratch.makeTemporaryDirectory()).makeCLI()
    let grokExecutable = try GrokQuotaTestWorkspace(root: scratch.makeTemporaryDirectory()).makeAgent()

    let data = try await SystemReport.generate(
      pipeline: workspace.makePipeline(),
      quotaSources: QuotaSources(
        codex: CodexQuotaSource(tool: CommandLineTool(candidates: [codexExecutable])),
        claude: ClaudeQuotaSource(tool: CommandLineTool(candidates: [claudeExecutable])),
        grok: GrokQuotaSource(tool: CommandLineTool(candidates: [grokExecutable])),
      ),
      at: UsageFixture.timestamp,
    )

    try #expect(keyPaths(of: JSONSerialization.jsonObject(with: data)).sorted() == Self.reportKeyPaths.sorted())
  }

  private static let reportKeyPaths =
    [
      "generatedAt",
      "quota.claude.snapshot.plan",
      "quota.claude.snapshot.windows[].resetsAt",
      "quota.claude.snapshot.windows[].title",
      "quota.claude.snapshot.windows[].usedPercent",
      "quota.claude.state",
      "quota.codex.snapshot.credits.balance.amount",
      "quota.codex.snapshot.plan",
      "quota.codex.snapshot.resetCredits.availableCount",
      "quota.codex.snapshot.resetCredits.credits[].expiresAt",
      "quota.codex.snapshot.resetCredits.credits[].id",
      "quota.codex.snapshot.resetCredits.credits[].title",
      "quota.codex.snapshot.windows[].resetsAt",
      "quota.codex.snapshot.windows[].title",
      "quota.codex.snapshot.windows[].usedPercent",
      "quota.codex.state",
      "quota.grok.snapshot.plan",
      "quota.grok.snapshot.windows[].resetsAt",
      "quota.grok.snapshot.windows[].title",
      "quota.grok.snapshot.windows[].usedPercent",
      "quota.grok.state",
      "usage.ingestion.events.claude",
      "usage.ingestion.events.codex",
      "usage.ingestion.events.grok",
      "usage.ingestion.events.piAgent",
      "usage.ingestion.logRoots[].exists",
      "usage.ingestion.logRoots[].path",
      "usage.ingestion.logRoots[].provider",
      "usage.ingestion.malformedLines.claude",
      "usage.ingestion.malformedLines.codex",
      "usage.ingestion.malformedLines.grok",
      "usage.ingestion.malformedLines.piAgent",
      "usage.ingestion.trackedFiles.claude",
      "usage.ingestion.trackedFiles.codex",
      "usage.ingestion.trackedFiles.grok",
      "usage.ingestion.trackedFiles.piAgent",
      "usage.ingestion.unpricedModels",
      "usage.snapshot.summary.last7Days.costChange.increase.fraction",
      "usage.snapshot.summary.last7Days.current.cost",
      "usage.snapshot.summary.last7Days.current.processedTokens",
      "usage.snapshot.summary.today.costChange.increase.fraction",
      "usage.snapshot.summary.today.current.cost",
      "usage.snapshot.summary.today.current.processedTokens",
    ]
    + ["claude", "codex", "grok", "piAgent"].flatMap { provider in
      [
        "dailyLast30Days[].date",
        "dailyLast30Days[].usage.cost",
        "dailyLast30Days[].usage.processedTokens",
        "periods.last30Days.total.cost",
        "periods.last30Days.total.processedTokens",
        "periods.last7Days.total.cost",
        "periods.last7Days.total.processedTokens",
        "periods.today.total.cost",
        "periods.today.total.processedTokens",
      ].map { "usage.snapshot.providers.\(provider).\($0)" }
    }
    + ["claude", "codex", "piAgent"].flatMap { provider in
      ["today", "last7Days", "last30Days"].flatMap { period in
        ["id", "modelName", "usage.cost", "usage.processedTokens"].map {
          "usage.snapshot.providers.\(provider).periods.\(period).models[].\($0)"
        }
      }
    }

  private static let codexQuotaResponse = """
    {"id":2,"result":{"rateLimits":{"limitId":"codex","planType":"prolite","primary":{"usedPercent":25,\
    "windowDurationMins":300,"resetsAt":1787698800},"secondary":{"usedPercent":40,\
    "windowDurationMins":10080,"resetsAt":1788134400},"credits":{"hasCredits":true,"unlimited":false,\
    "balance":"1234.5"}},"rateLimitsByLimitId":{"codex_spark":{\
    "limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,\
    "resetsAt":1787698800}}},"rateLimitResetCredits":{"availableCount":1,\
    "credits":[\(CodexQuotaTestWorkspace.resetCredit)]}}}
    """

  private let workspace: UsageTestWorkspace

  private let scratch = Scratch()

  private func keyPaths(of value: Any, prefix: String = "") -> Set<String> {
    switch value {
    case let object as [String: Any] where !object.isEmpty:
      object.reduce(into: []) { paths, entry in
        let path = prefix.isEmpty ? entry.key : "\(prefix).\(entry.key)"
        paths.formUnion(keyPaths(of: entry.value, prefix: path))
      }

    case let array as [Any] where !array.isEmpty:
      array.reduce(into: []) { paths, element in
        paths.formUnion(keyPaths(of: element, prefix: prefix + "[]"))
      }

    default:
      [prefix]
    }
  }
}
