import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaResetModelTests: XCTestCase {
    private var workspace: CodexQuotaTestWorkspace!

    override func setUpWithError() throws {
        workspace = try CodexQuotaTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    @MainActor
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let executable = try workspace.makeResetExecutable()
        let model = try await loadModel(executable: executable)
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.beginReset(creditID: "credit-a")
        XCTAssertEqual(model.resetState, .confirming(attempt))
        model.cancelReset()
        model.submitReset()
        XCTAssertEqual(model.resetState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testConsumeIsSingleFlightAndForcesAuthoritativeRefreshInsideCooldown() async throws {
        let after = CodexQuotaTestWorkspace.resetQuotaResponse(count: 0, credits: "[]", usedPercent: 17)
        let executable = try workspace.makeResetExecutable(
            onConsume: "printf '%s\\n' '\(after)' > '\(workspace.quotaResponseFile.path)'"
        )
        let model = try await loadModel(executable: executable)
        model.beginReset(creditID: "credit-a")
        model.submitReset()
        model.submitReset()
        model.beginReset(creditID: "credit-a")
        model.refresh(force: true)
        XCTAssertEqual(model.resetState, .submitting)
        try await waitUntil { !model.isResetting }

        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(model.snapshot?.account?.limits?.fiveHour?.remainingPercent, 83)
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 0)
        XCTAssertNil(model.refreshFailure)
        XCTAssertEqual(try lines(in: workspace.consumeRequestsFile).count, 1)
        XCTAssertEqual(try lines(in: workspace.readRequestsFile).count, 2)
    }

    @MainActor
    func testSuccessfulConsumeAndFailedRefreshRemainSeparateAndRefreshCanRecover() async throws {
        let executable = try workspace.makeResetExecutable(
            onConsume: "rm '\(workspace.quotaResponseFile.path)'"
        )
        let model = try await loadModel(executable: executable)
        let original = model.snapshot
        model.beginReset(creditID: "credit-a")
        model.submitReset()
        try await waitUntil { !model.isResetting }

        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(model.snapshot, original)
        XCTAssertEqual(model.refreshFailure, .sessionFailed)
        XCTAssertFalse(model.canChooseReset)

        try CodexQuotaTestWorkspace.resetQuotaResponse(count: 0, credits: "[]", usedPercent: 0)
            .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertNil(model.refreshFailure)
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 0)
        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(try lines(in: workspace.consumeRequestsFile).count, 1)
    }

    @MainActor
    func testLostResponseKeepsIntentAcrossRefreshAndRetriesIdenticalRequest() async throws {
        let marker = workspace.root.appending(path: "consumed")
        let after = CodexQuotaTestWorkspace.resetQuotaResponse(count: 0, credits: "[]")
        let executable = try workspace.makeResetExecutable(
            consumeResponse: "{\"id\":2,\"result\":{\"outcome\":\"alreadyRedeemed\"}}",
            onConsume: """
                if [ ! -f '\(marker.path)' ]; then
                  touch '\(marker.path)'
                  printf '%s\\n' '\(after)' > '\(workspace.quotaResponseFile.path)'
                  exit 0
                fi
                """
        )
        let model = try await loadModel(executable: executable)
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.submitReset()
        try await waitUntil { !model.isResetting }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .unavailable(.sessionFailed)))
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 0)

        // View dismissal cannot discard an unresolved intent or replace its key.
        model.cancelReset()
        model.beginReset(creditID: "credit-b")
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .unavailable(.sessionFailed)))
        XCTAssertFalse(model.canChooseReset)
        XCTAssertEqual(try lines(in: workspace.consumeRequestsFile).count, 1)

        model.submitReset()
        try await waitUntil { !model.isResetting }
        XCTAssertEqual(model.resetState, .completed(.alreadyRedeemed))
        let requests = try lines(in: workspace.consumeRequestsFile)
        XCTAssertEqual(requests.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(requests[0].utf8)) as? NSDictionary
        let second = try JSONSerialization.jsonObject(with: Data(requests[1].utf8)) as? NSDictionary
        XCTAssertEqual(first, second)
    }

    @MainActor
    func testTimeoutDoesNotAutomaticallyRetryOrDiscardIntent() async throws {
        let executable = try workspace.makeResetExecutable(onConsume: "sleep 10")
        let model = try await loadModel(executable: executable, timeout: .milliseconds(200))
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.submitReset()
        try await waitUntil { !model.isResetting }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .unavailable(.timedOut)))
        XCTAssertEqual(try lines(in: workspace.consumeRequestsFile).count, 1)
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 1)
    }

    @MainActor
    func testFailureBeforeTheWriteRemainsCancellable() async throws {
        let stalled = workspace.root.appending(path: "stall")
        let executable = try workspace.makeResetExecutable(
            onStart: "if [ -f '\(stalled.path)' ]; then sleep 10; fi"
        )
        let model = try await loadModel(executable: executable, timeout: .milliseconds(200))
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        try Data().write(to: stalled)
        model.submitReset()
        try await waitUntil { !model.isResetting }
        XCTAssertEqual(model.resetState, .confirming(attempt, failure: .unavailable(.timedOut)))
        model.cancelReset()
        XCTAssertEqual(model.resetState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        for credits in ["[]", "null"] {
            let executable = try workspace.makeResetExecutable()
            let model = try await loadModel(executable: executable)
            model.beginReset(creditID: "credit-a")
            try CodexQuotaTestWorkspace.resetQuotaResponse(count: 0, credits: credits)
                .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
            model.refresh(force: true)
            try await waitUntil { !model.isRefreshing }
            XCTAssertEqual(model.resetState, .idle)
            model.submitReset()
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        }
    }

    @MainActor
    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let executable = try workspace.makeResetExecutable()
        let model = try await loadModel(executable: executable)
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.refresh(force: true)
        model.submitReset()
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.resetState, .confirming(attempt))
        try await waitUntil { !model.isRefreshing }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        model.submitReset()
        try await waitUntil { !model.isResetting }
        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(try lines(in: workspace.consumeRequestsFile).count, 1)
    }

    @MainActor
    private func loadModel(executable: URL, timeout: Duration = .seconds(15)) async throws -> CodexQuotaModel {
        let model = CodexQuotaModel(quotaService: CodexQuotaService(executableURL: executable, timeout: timeout))
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        XCTAssertNotNil(model.snapshot)
        return model
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "condition did not become true before the deadline")
    }

    private func lines(in file: URL) throws -> [Substring] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    }
}
