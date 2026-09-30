import Foundation
import XCTest

@testable import Koogo

final class SystemReportTests: UsageWorkspaceTestCase {
    func testReportDescribesUsagePipelineAndQuotaOutcome() async throws {
        let quotaWorkspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())

        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )

        let data = try await SystemReport.generate(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            quotaSources: [
                .codex: CodexQuotaSource(executableCandidates: [try quotaWorkspace.makeAppServer()]),
                .claude: ClaudeQuotaSource(executableCandidates: []),
                .grok: GrokQuotaSource(executableCandidates: []),
            ],
            at: now
        )
        let report = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(report["generatedAt"] as? String, "2026-08-25T18:00:00Z")
        let usage = try XCTUnwrap(report["usage"] as? [String: Any])
        let ingestion = try XCTUnwrap(usage["ingestion"] as? [String: Any])
        XCTAssertEqual(
            ingestion["trackedFiles"] as? [String: Int],
            ["codex": 1, "claude": 0, "piAgent": 0, "grok": 0]
        )
        XCTAssertEqual(ingestion["events"] as? [String: Int], ["codex": 1, "claude": 0, "piAgent": 0, "grok": 0])
        XCTAssertEqual(ingestion["unpricedModels"] as? [String], [])
        let logRoots = try XCTUnwrap(ingestion["logRoots"] as? [[String: Any]])
        XCTAssertEqual(logRoots.count, 5)
        XCTAssertTrue(logRoots.allSatisfy { $0["exists"] as? Bool == true })

        let quota = try XCTUnwrap(report["quota"] as? [String: Any])
        let codex = try XCTUnwrap(quota["codex"] as? [String: Any])
        XCTAssertEqual(codex["state"] as? String, "available")
        let claude = try XCTUnwrap(quota["claude"] as? [String: Any])
        XCTAssertEqual(claude["state"] as? String, "unavailable")
        XCTAssertEqual(claude["reason"] as? String, "binaryNotFound")
        XCTAssertNil(claude["snapshot"])
        let grok = try XCTUnwrap(quota["grok"] as? [String: Any])
        XCTAssertEqual(grok["state"] as? String, "unavailable")
        XCTAssertEqual(grok["reason"] as? String, "binaryNotFound")
        XCTAssertNil(grok["snapshot"])
    }

    func testReportKeyPathsAreStable() async throws {
        let quotaWorkspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())

        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        try workspace.write(claudeLog(output: 40), to: workspace.claudeProjects.appending(path: "project/main.jsonl"))
        try workspace.write(
            piAssistant(id: "assistant", parentID: nil, model: "model-a", usage: piUsage(input: 100, cost: "0.1"))
                + "\n",
            to: workspace.piSessions.appending(path: "session.jsonl")
        )
        let grokSession = workspace.grokSessions.appending(path: "project/s", directoryHint: .isDirectory)
        try workspace.write("{}", to: grokSession.appending(path: "summary.json"))
        try workspace.write(grokTurn(eventID: "s-1") + "\n", to: grokSession.appending(path: "updates.jsonl"))

        let codexExecutable = try quotaWorkspace.makeAppServer(quotaResponse: codexQuotaResponse)
        let claudeExecutable = try ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory()).makeCLI()
        let grokExecutable = try GrokQuotaTestWorkspace(root: try makeTemporaryDirectory()).makeAgent()

        let data = try await SystemReport.generate(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            quotaSources: [
                .codex: CodexQuotaSource(executableCandidates: [codexExecutable]),
                .claude: ClaudeQuotaSource(executableCandidates: [claudeExecutable]),
                .grok: GrokQuotaSource(executableCandidates: [grokExecutable]),
            ],
            at: now
        )

        XCTAssertEqual(keyPaths(of: try JSONSerialization.jsonObject(with: data)).sorted(), reportKeyPaths.sorted())
    }
}

private let reportKeyPaths =
    [
        "generatedAt",
        "quota.claude.snapshot.windows[].resetsAt",
        "quota.claude.snapshot.windows[].title",
        "quota.claude.snapshot.windows[].usedPercent",
        "quota.claude.state",
        "quota.codex.snapshot.resetCredits.availableCount",
        "quota.codex.snapshot.resetCredits.credits[].expiresAt",
        "quota.codex.snapshot.resetCredits.credits[].id",
        "quota.codex.snapshot.resetCredits.credits[].title",
        "quota.codex.snapshot.windows[].resetsAt",
        "quota.codex.snapshot.windows[].title",
        "quota.codex.snapshot.windows[].usedPercent",
        "quota.codex.state",
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
        "usage.snapshot.providers.codex.favorite.reasoningEffort",
        "usage.snapshot.summary.last30Days.costChange.increase.fraction",
        "usage.snapshot.summary.last30Days.current.costUSD",
        "usage.snapshot.summary.last30Days.current.processedTokens",
        "usage.snapshot.summary.today.costChange.increase.fraction",
        "usage.snapshot.summary.today.current.costUSD",
        "usage.snapshot.summary.today.current.processedTokens",
    ]
    + ["claude", "codex", "grok", "piAgent"].flatMap { provider in
        [
            "dailyLast30Days.days[].date",
            "dailyLast30Days.days[].usage.costUSD",
            "dailyLast30Days.days[].usage.processedTokens",
            "dailyLast30Days.range[]",
            "favorite.modelName",
            "last30Days.costUSD",
            "last30Days.processedTokens",
            "last7Days.costUSD",
            "last7Days.processedTokens",
            "today.costUSD",
            "today.processedTokens",
        ].map { "usage.snapshot.providers.\(provider).\($0)" }
    }

private let codexQuotaResponse = """
    {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,\
    "windowDurationMins":300,"resetsAt":1787698800},"secondary":{"usedPercent":40,\
    "windowDurationMins":10080,"resetsAt":1788134400}},"rateLimitsByLimitId":{"codex_spark":{\
    "limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,\
    "resetsAt":1787698800}}},"rateLimitResetCredits":{"availableCount":1,\
    "credits":[\(CodexQuotaTestWorkspace.resetCredit)]}}}
    """

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
