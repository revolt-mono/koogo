import Foundation
import XCTest

@testable import Koogo

final class ClaudeQuotaModelTests: XCTestCase {
    @MainActor
    func testRefreshCoalescesCachesAndRecoversFromStaleData() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeCLI()
        let model = ClaudeQuotaModel(quotaService: ClaudeQuotaService(executableCandidates: [executable]))
        model.refresh()
        model.refresh(force: true)
        XCTAssertEqual(model.state, .loading)
        try await waitUntil { !model.isRefreshing }
        let snapshot = try XCTUnwrap(model.state.snapshot)
        XCTAssertEqual(snapshot.account?.session?.remainingPercent, 88)
        model.refresh()
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(try String(contentsOf: workspace.callsFile, encoding: .utf8), "usage\n")

        try ClaudeQuotaTestWorkspace.response(rateLimits: "null")
            .write(to: workspace.outputFile, atomically: true, encoding: .utf8)
        model.refresh(force: true)
        XCTAssertEqual(model.state, .available(snapshot, stale: nil))
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(snapshot, stale: .emptyLimits))

        try ClaudeQuotaTestWorkspace.response().write(to: workspace.outputFile, atomically: true, encoding: .utf8)
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(snapshot, stale: nil))
    }

    @MainActor
    func testMissingCLIBecomesUnavailableAndRetryCanRecover() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = ClaudeQuotaModel(
            quotaService: ClaudeQuotaService(executableCandidates: [workspace.root.appending(path: "claude")])
        )
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .unavailable(.binaryNotFound))
        _ = try workspace.makeCLI()
        model.refresh(force: true)
        XCTAssertEqual(model.state, .unavailable(.binaryNotFound))
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state.snapshot?.account?.weekly?.remainingPercent, 71)
    }
}
