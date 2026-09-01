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
            quotaService: CodexQuotaService(executableURL: executable),
            at: usageTestTimestamp
        )
        let report = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let usage = try XCTUnwrap(report["usage"] as? [String: Any])
        let ingestion = try XCTUnwrap(usage["ingestion"] as? [String: Any])
        XCTAssertEqual(ingestion["trackedFiles"] as? [String: Int], ["codex": 1])
        XCTAssertEqual(ingestion["events"] as? [String: Int], ["codex": 1])
        XCTAssertEqual(ingestion["unpricedModels"] as? [String], [])
        let logRoots = try XCTUnwrap(usage["logRoots"] as? [[String: Any]])
        XCTAssertEqual(logRoots.count, 4)
        XCTAssertTrue(logRoots.allSatisfy { $0["exists"] as? Bool == true })
        XCTAssertNotNil(usage["snapshot"])

        let quota = try XCTUnwrap(report["quota"] as? [String: Any])
        XCTAssertEqual(quota["state"] as? String, "available")
        XCTAssertNotNil(quota["snapshot"])
    }

    func testReportCarriesQuotaUnavailabilityReason() async throws {
        let usageWorkspace = try UsageTestWorkspace()
        defer { try? usageWorkspace.remove() }
        let missing = usageWorkspace.root.appending(path: "missing-codex")

        let data = try await SystemReport.generate(
            locations: usageWorkspace.locations,
            quotaService: CodexQuotaService(executableURL: missing),
            at: usageTestTimestamp
        )
        let report = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let quota = try XCTUnwrap(report["quota"] as? [String: Any])
        XCTAssertEqual(quota["state"] as? String, "unavailable")
        XCTAssertEqual(quota["reason"] as? String, "sessionFailed")
    }
}
