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
            codexQuotaService: CodexQuotaService(executableCandidates: [try quotaWorkspace.makeAppServer()]),
            grokQuotaService: GrokQuotaService(authURL: workspace.root.appending(path: "missing-auth.json")),
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
        let grok = try XCTUnwrap(quota["grok"] as? [String: Any])
        XCTAssertEqual(grok["state"] as? String, "unavailable")
        XCTAssertEqual(grok["reason"] as? String, "signedOut")
        XCTAssertNil(grok["snapshot"])
    }

    /// The single owner of the `--report` shape: one priced event per provider and both quotas
    /// available. Change `reportKeyPaths` only with an intended shape change.
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
        let grokAuth = workspace.root.appending(path: "auth.json")
        try writeGrokSession(expiresAt: "2999-01-01T00:00:00Z", to: grokAuth)

        let data = try await SystemReport.generate(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            codexQuotaService: CodexQuotaService(executableCandidates: [codexExecutable]),
            grokQuotaService: GrokQuotaService(authURL: grokAuth) { _ in try grokBillingReply(grokBilling) },
            at: now
        )

        XCTAssertEqual(keyPaths(of: try JSONSerialization.jsonObject(with: data)).sorted(), reportKeyPaths)
    }
}

private let reportKeyPaths = [
    "generatedAt",
    "quota.codex.snapshot.account.limits.fiveHour.remainingPercent",
    "quota.codex.snapshot.account.limits.fiveHour.resetsAt",
    "quota.codex.snapshot.account.limits.weekly.remainingPercent",
    "quota.codex.snapshot.account.limits.weekly.resetsAt",
    "quota.codex.snapshot.account.resetCredits.availableCount",
    "quota.codex.snapshot.account.resetCredits.credits[].expiresAt",
    "quota.codex.snapshot.account.resetCredits.credits[].id",
    "quota.codex.snapshot.account.resetCredits.credits[].title",
    "quota.codex.snapshot.models[].id",
    "quota.codex.snapshot.models[].limits.fiveHour.remainingPercent",
    "quota.codex.snapshot.models[].limits.fiveHour.resetsAt",
    "quota.codex.snapshot.models[].title",
    "quota.codex.state",
    "quota.grok.snapshot.period",
    "quota.grok.snapshot.window.remainingPercent",
    "quota.grok.snapshot.window.resetsAt",
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
    "usage.snapshot.providers.claude.dailyMonth.days[].date",
    "usage.snapshot.providers.claude.dailyMonth.days[].usage.costUSD",
    "usage.snapshot.providers.claude.dailyMonth.days[].usage.processedTokens",
    "usage.snapshot.providers.claude.dailyMonth.range[]",
    "usage.snapshot.providers.claude.favorite.modelName",
    "usage.snapshot.providers.claude.month.costUSD",
    "usage.snapshot.providers.claude.month.processedTokens",
    "usage.snapshot.providers.claude.today.costUSD",
    "usage.snapshot.providers.claude.today.processedTokens",
    "usage.snapshot.providers.claude.week.costUSD",
    "usage.snapshot.providers.claude.week.processedTokens",
    "usage.snapshot.providers.codex.dailyMonth.days[].date",
    "usage.snapshot.providers.codex.dailyMonth.days[].usage.costUSD",
    "usage.snapshot.providers.codex.dailyMonth.days[].usage.processedTokens",
    "usage.snapshot.providers.codex.dailyMonth.range[]",
    "usage.snapshot.providers.codex.favorite.modelName",
    "usage.snapshot.providers.codex.favorite.reasoningEffort",
    "usage.snapshot.providers.codex.month.costUSD",
    "usage.snapshot.providers.codex.month.processedTokens",
    "usage.snapshot.providers.codex.today.costUSD",
    "usage.snapshot.providers.codex.today.processedTokens",
    "usage.snapshot.providers.codex.week.costUSD",
    "usage.snapshot.providers.codex.week.processedTokens",
    "usage.snapshot.providers.grok.dailyMonth.days[].date",
    "usage.snapshot.providers.grok.dailyMonth.days[].usage.costUSD",
    "usage.snapshot.providers.grok.dailyMonth.days[].usage.processedTokens",
    "usage.snapshot.providers.grok.dailyMonth.range[]",
    "usage.snapshot.providers.grok.favorite.modelName",
    "usage.snapshot.providers.grok.month.costUSD",
    "usage.snapshot.providers.grok.month.processedTokens",
    "usage.snapshot.providers.grok.today.costUSD",
    "usage.snapshot.providers.grok.today.processedTokens",
    "usage.snapshot.providers.grok.week.costUSD",
    "usage.snapshot.providers.grok.week.processedTokens",
    "usage.snapshot.providers.piAgent.dailyMonth.days[].date",
    "usage.snapshot.providers.piAgent.dailyMonth.days[].usage.costUSD",
    "usage.snapshot.providers.piAgent.dailyMonth.days[].usage.processedTokens",
    "usage.snapshot.providers.piAgent.dailyMonth.range[]",
    "usage.snapshot.providers.piAgent.favorite.modelName",
    "usage.snapshot.providers.piAgent.month.costUSD",
    "usage.snapshot.providers.piAgent.month.processedTokens",
    "usage.snapshot.providers.piAgent.today.costUSD",
    "usage.snapshot.providers.piAgent.today.processedTokens",
    "usage.snapshot.providers.piAgent.week.costUSD",
    "usage.snapshot.providers.piAgent.week.processedTokens",
    "usage.snapshot.summary.month.costChange.increase.fraction",
    "usage.snapshot.summary.month.current.costUSD",
    "usage.snapshot.summary.month.current.processedTokens",
    "usage.snapshot.summary.today.costChange.increase.fraction",
    "usage.snapshot.summary.today.current.costUSD",
    "usage.snapshot.summary.today.current.processedTokens",
]

/// Account five-hour and weekly windows, one model limit and one reset credit.
private let codexQuotaResponse = """
    {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,\
    "windowDurationMins":300,"resetsAt":1787698800},"secondary":{"usedPercent":40,\
    "windowDurationMins":10080,"resetsAt":1788134400}},"rateLimitsByLimitId":{"codex_spark":{\
    "limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,\
    "resetsAt":1787698800}}},"rateLimitResetCredits":{"availableCount":1,\
    "credits":[\(CodexQuotaTestWorkspace.resetCredit)]}}}
    """

private let grokBilling = """
    {"config":{"creditUsagePercent":25,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "end":"2026-09-01T00:00:00Z"}}}
    """

/// Object keys join with `.`, array elements append `[]` and are unioned, and scalars,
/// null and empty containers end a path.
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
