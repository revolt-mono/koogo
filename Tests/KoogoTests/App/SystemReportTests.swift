import Foundation
import XCTest

@testable import Koogo

final class SystemReportTests: XCTestCase {
    func testReportDescribesUsagePipelineAndQuotaOutcome() async throws {
        let usageWorkspace = try UsageTestWorkspace()
        defer { try? usageWorkspace.remove() }
        let quotaWorkspace = try CodexQuotaTestWorkspace()
        defer { try? quotaWorkspace.remove() }

        try usageWorkspace.write(
            codexLog(input: 100, output: 20),
            to: usageWorkspace.locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let executable = try quotaWorkspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )

        let data = try await SystemReport.generate(
            locations: usageWorkspace.locations,
            codexQuotaService: CodexQuotaService(executableURL: executable),
            grokQuotaService: GrokQuotaService(authURL: usageWorkspace.root.appending(path: "missing-auth.json")),
            at: usageTestTimestamp
        )
        let report = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

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
        XCTAssertNotNil(usage["snapshot"])

        let quota = try XCTUnwrap(report["quota"] as? [String: Any])
        let codex = try XCTUnwrap(quota["codex"] as? [String: Any])
        XCTAssertEqual(codex["state"] as? String, "available")
        XCTAssertNotNil(codex["snapshot"])
        XCTAssertNil(codex["reason"])
        let grok = try XCTUnwrap(quota["grok"] as? [String: Any])
        XCTAssertEqual(grok["state"] as? String, "unavailable")
        XCTAssertEqual(grok["reason"] as? String, "signedOut")
    }

    func testReportCarriesQuotaUnavailabilityReason() async throws {
        let usageWorkspace = try UsageTestWorkspace()
        defer { try? usageWorkspace.remove() }
        let missing = usageWorkspace.root.appending(path: "missing-codex")

        let data = try await SystemReport.generate(
            locations: usageWorkspace.locations,
            codexQuotaService: CodexQuotaService(executableURL: missing),
            grokQuotaService: GrokQuotaService(authURL: missing),
            at: usageTestTimestamp
        )
        let report = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let quota = try XCTUnwrap(report["quota"] as? [String: Any])
        let codex = try XCTUnwrap(quota["codex"] as? [String: Any])
        XCTAssertEqual(codex["state"] as? String, "unavailable")
        XCTAssertEqual(codex["reason"] as? String, "sessionFailed")
        XCTAssertNil(codex["snapshot"])
    }
}
