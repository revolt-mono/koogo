import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaModelTests: XCTestCase {
    private var workspace: CodexQuotaTestWorkspace!
    private var root: URL { workspace.root }

    override func setUpWithError() throws {
        workspace = try CodexQuotaTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    @MainActor
    func testRefreshesCoalesceAndCache() async throws {
        let launches = root.appending(path: "launches")
        let executable = try workspace.makeExecutable(
            launchMarker: launches,
            responseDelay: 0.2,
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableURL: executable)
        )

        model.refresh()
        model.refresh()
        XCTAssertEqual(model.state, .loading)

        let deadline = ContinuousClock.now + .seconds(2)
        while model.state == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        guard case .available(let snapshot) = model.state else {
            return XCTFail("expected available quota")
        }
        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 75)
        model.refresh()
        try await Task.sleep(for: .milliseconds(100))

        let launchCount = try String(contentsOf: launches, encoding: .utf8)
            .split(separator: "\n")
            .count
        XCTAssertEqual(launchCount, 1)
    }

    @MainActor
    func testExistingSnapshotRemainsUntilFailedRefreshCompletes() async throws {
        let executable = try workspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableURL: executable),
            cooldown: .zero
        )
        model.refresh()
        var deadline = ContinuousClock.now + .seconds(2)
        while model.state == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .available(let snapshot) = model.state else {
            return XCTFail("expected available quota")
        }

        try FileManager.default.removeItem(at: executable)
        model.refresh()
        XCTAssertEqual(model.state, .available(snapshot))
        deadline = ContinuousClock.now + .seconds(2)
        while model.state == .available(snapshot), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .unavailable(.sessionFailed))
    }
}
