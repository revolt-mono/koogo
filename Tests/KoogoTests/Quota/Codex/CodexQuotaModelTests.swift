import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaModelTests: XCTestCase {
    @MainActor
    func testRefreshesCoalesceAndCache() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableCandidates: [try workspace.makeAppServer()])
        )

        model.refresh()
        model.refresh()
        XCTAssertEqual(model.state, .loading)
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.snapshot?.account?.limits?.fiveHour?.remainingPercent, 75)
        model.refresh()
        XCTAssertFalse(model.isBusy)
        XCTAssertEqual(try workspace.lines(in: workspace.readRequestsFile).count, 1)
    }

    @MainActor
    func testFailedRefreshKeepsSnapshotAndMarksItStale() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer()
        let model = try await loadModel(executable: executable)
        let snapshot = try XCTUnwrap(model.snapshot)

        try FileManager.default.removeItem(at: executable)
        model.refresh(force: true)
        XCTAssertEqual(model.state, .available(snapshot, stale: nil))
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.state, .available(snapshot, stale: .binaryNotFound))
    }

    @MainActor
    func testRetryFromUnavailableKeepsTheReasonWhileInFlight() async throws {
        let model = CodexQuotaModel(quotaService: CodexQuotaService(executableCandidates: []))
        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.state, .unavailable(.binaryNotFound))

        model.refresh(force: true)
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.state, .unavailable(.binaryNotFound))
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.state, .unavailable(.binaryNotFound))
    }

    @MainActor
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = try await loadModel(executable: try workspace.makeAppServer())
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
    func testConfirmationForACreditThatExpiresBeforeSubmitIsRefused() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        var now = Date.distantPast
        let model = try await loadModel(executable: try workspace.makeAppServer(), now: { now })
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }

        now = try XCTUnwrap(attempt.credit.expiresAt)
        model.submitReset()
        XCTAssertEqual(model.resetState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testConsumeIsSingleFlightAndForcesAuthoritativeRefreshInsideCooldown() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let after = CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 17, resetCount: 0, credits: "[]")
        let executable = try workspace.makeAppServer(
            onConsume: "printf '%s\\n' '\(after)' > '\(workspace.quotaResponseFile.path)'"
        )
        let model = try await loadModel(executable: executable)
        model.beginReset(creditID: "credit-a")
        model.submitReset()
        model.submitReset()
        model.beginReset(creditID: "credit-a")
        model.refresh(force: true)
        XCTAssertEqual(model.resetState, .submitting)
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.resetState, .completed(.reset))
        guard case .available(let snapshot, stale: nil) = model.state else { return XCTFail("expected fresh quota") }
        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 83)
        XCTAssertEqual(snapshot.account?.resetCredits?.availableCount, 0)
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
        XCTAssertEqual(try workspace.lines(in: workspace.readRequestsFile).count, 2)
    }

    @MainActor
    func testSuccessfulConsumeAndFailedRefreshRemainSeparateAndRefreshCanRecover() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            onConsume: "rm '\(workspace.quotaResponseFile.path)'"
        )
        let model = try await loadModel(executable: executable)
        let original = try XCTUnwrap(model.snapshot)
        model.beginReset(creditID: "credit-a")
        model.submitReset()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(model.state, .available(original, stale: .sessionFailed))
        XCTAssertFalse(model.canChooseReset)

        try CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 0, resetCount: 0, credits: "[]")
            .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
        model.refresh(force: true)
        try await waitUntil { !model.isBusy }
        guard case .available(let snapshot, stale: nil) = model.state else { return XCTFail("expected fresh quota") }
        XCTAssertEqual(snapshot.account?.resetCredits?.availableCount, 0)
        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
    }

    @MainActor
    func testLostResponseKeepsIntentAcrossRefreshAndRetriesIdenticalRequest() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let marker = workspace.root.appending(path: "consumed")
        let after = CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 0, credits: "[]")
        let executable = try workspace.makeAppServer(
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
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .sessionFailed))
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 0)

        // View dismissal cannot discard an unresolved intent or replace its key.
        model.cancelReset()
        model.beginReset(creditID: "credit-b")
        model.refresh(force: true)
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .sessionFailed))
        XCTAssertFalse(model.canChooseReset)
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)

        model.submitReset()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetState, .completed(.alreadyRedeemed))
        let requests = try workspace.lines(in: workspace.consumeRequestsFile)
        XCTAssertEqual(requests.count, 2)
        let first = try JSONSerialization.jsonObject(with: Data(requests[0].utf8)) as? NSDictionary
        let second = try JSONSerialization.jsonObject(with: Data(requests[1].utf8)) as? NSDictionary
        XCTAssertEqual(first, second)
    }

    @MainActor
    func testTimeoutDoesNotAutomaticallyRetryOrDiscardIntent() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(onConsume: "sleep 10")
        let model = try await loadModel(executable: executable, timeout: .seconds(1))
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.submitReset()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetState, .unconfirmed(attempt, .timedOut))
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 1)
    }

    @MainActor
    func testFailureBeforeTheWriteRemainsCancellable() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let stalled = workspace.root.appending(path: "stall")
        let executable = try workspace.makeAppServer(
            onStart: "if [ -f '\(stalled.path)' ]; then sleep 10; fi"
        )
        let model = try await loadModel(executable: executable, timeout: .seconds(1))
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        try Data().write(to: stalled)
        model.submitReset()
        // Both the consume and the read after it stall until the timeout kills their process groups.
        try await waitUntil(timeout: .seconds(10)) { !model.isBusy }
        XCTAssertEqual(model.resetState, .confirming(attempt, failure: .timedOut))
        model.cancelReset()
        XCTAssertEqual(model.resetState, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testRejectedConsumeDropsConfirmationWhenReadRemovesCredit() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let stalled = workspace.root.appending(path: "stall")
        let executable = try workspace.makeAppServer(
            onStart: "if [ -f '\(stalled.path)' ]; then rm '\(stalled.path)'; sleep 10; fi"
        )
        let model = try await loadModel(executable: executable, timeout: .seconds(1))
        model.beginReset(creditID: "credit-a")
        guard case .confirming = model.resetState else { return XCTFail("expected confirmation") }

        try CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 0, credits: "[]")
            .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
        try Data().write(to: stalled)
        model.submitReset()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.resetState, .idle)
        XCTAssertEqual(model.snapshot?.account?.resetCredits?.availableCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        for credits in ["[]", "null"] {
            let model = try await loadModel(executable: try workspace.makeAppServer())
            model.beginReset(creditID: "credit-a")
            try CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 0, credits: credits)
                .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
            model.refresh(force: true)
            try await waitUntil { !model.isBusy }
            XCTAssertEqual(model.resetState, .idle)
            model.submitReset()
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        }
    }

    @MainActor
    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = try await loadModel(executable: try workspace.makeAppServer())
        model.beginReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.resetState else { return XCTFail("expected confirmation") }
        model.refresh(force: true)
        model.submitReset()
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.resetState, .confirming(attempt))
        try await waitUntil { !model.isBusy }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        model.submitReset()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetState, .completed(.reset))
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
    }

    @MainActor
    private func loadModel(
        executable: URL,
        timeout: Duration = .seconds(15),
        now: @escaping @MainActor () -> Date = { .now }
    ) async throws -> CodexQuotaModel {
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableCandidates: [executable], timeout: timeout),
            now: now
        )
        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertNotNil(model.snapshot)
        return model
    }
}
