import Foundation
import XCTest

@testable import Koogo

final class QuotaModelCodexResetTests: XCTestCase {
    @MainActor
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = try await loadModel(executable: try workspace.makeAppServer())
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.codexReset else { return XCTFail("expected confirmation") }
        model.beginCodexReset(creditID: "credit-a")
        XCTAssertEqual(model.codexReset, .confirming(attempt))
        model.cancelCodexReset()
        model.submitCodexReset()
        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testConfirmationForACreditThatExpiresBeforeSubmitIsRefused() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        var now = Date.distantPast
        let model = try await loadModel(executable: try workspace.makeAppServer(), now: { now })
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.codexReset else { return XCTFail("expected confirmation") }

        now = try XCTUnwrap(attempt.credit.expiresAt)
        model.submitCodexReset()
        XCTAssertEqual(model.codexReset, .idle)
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
        model.beginCodexReset(creditID: "credit-a")
        model.submitCodexReset()
        model.submitCodexReset()
        model.beginCodexReset(creditID: "credit-a")
        model.refresh([.codex], force: true)
        guard case .submitting = model.codexReset else { return XCTFail("expected submitting") }
        try await waitUntil { !model.isBusy(.codex) }

        XCTAssertEqual(model.codexReset, .completed(.reset))
        guard case .available(let snapshot) = model.statuses[.codex].latest else {
            return XCTFail("expected fresh quota")
        }
        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 17)
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 0)
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
        model.beginCodexReset(creditID: "credit-a")
        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }

        XCTAssertEqual(model.codexReset, .completed(.reset))
        XCTAssertEqual(model.statuses[.codex].latest, .unavailable(.sessionFailed))
        XCTAssertFalse(model.canChooseCodexReset)

        try CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 0, resetCount: 0, credits: "[]")
            .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
        model.refresh([.codex], force: true)
        try await waitUntil { !model.isBusy(.codex) }
        guard case .available(let snapshot) = model.statuses[.codex].latest else {
            return XCTFail("expected fresh quota")
        }
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 0)
        XCTAssertEqual(model.codexReset, .completed(.reset))
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
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.codexReset else { return XCTFail("expected confirmation") }
        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .sessionFailed))
        XCTAssertEqual(model.codexResetCredits?.availableCount, 0)

        model.cancelCodexReset()
        model.beginCodexReset(creditID: "credit-b")
        model.refresh([.codex], force: true)
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .sessionFailed))
        XCTAssertFalse(model.canChooseCodexReset)
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)

        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.codexReset, .completed(.alreadyRedeemed))
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
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.codexReset else { return XCTFail("expected confirmation") }
        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .timedOut))
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
        XCTAssertEqual(model.codexResetCredits?.availableCount, 1)
    }

    @MainActor
    func testFailureBeforeTheWriteDropsTheConfirmationWithItsSnapshot() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let stalled = workspace.root.appending(path: "stall")
        let executable = try workspace.makeAppServer(
            onStart: "if [ -f '\(stalled.path)' ]; then sleep 10; fi"
        )
        let model = try await loadModel(executable: executable, timeout: .seconds(1))
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming = model.codexReset else { return XCTFail("expected confirmation") }
        try Data().write(to: stalled)
        model.submitCodexReset()
        try await waitUntil(timeout: .seconds(10)) { !model.isBusy(.codex) }
        XCTAssertEqual(model.statuses[.codex].latest, .unavailable(.timedOut))
        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertFalse(model.canChooseCodexReset)
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
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming = model.codexReset else { return XCTFail("expected confirmation") }

        try CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 0, credits: "[]")
            .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
        try Data().write(to: stalled)
        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }

        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertEqual(model.codexResetCredits?.availableCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
    }

    @MainActor
    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        for credits in ["[]", "null"] {
            let model = try await loadModel(executable: try workspace.makeAppServer())
            model.beginCodexReset(creditID: "credit-a")
            try CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 0, credits: credits)
                .write(to: workspace.quotaResponseFile, atomically: true, encoding: .utf8)
            model.refresh([.codex], force: true)
            try await waitUntil { !model.isBusy(.codex) }
            XCTAssertEqual(model.codexReset, .idle)
            model.submitCodexReset()
            XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        }
    }

    @MainActor
    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let model = try await loadModel(executable: try workspace.makeAppServer())
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.codexReset else { return XCTFail("expected confirmation") }
        model.refresh([.codex], force: true)
        model.submitCodexReset()
        XCTAssertTrue(model.isBusy(.codex))
        XCTAssertEqual(model.codexReset, .confirming(attempt))
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.consumeRequestsFile.path))
        model.submitCodexReset()
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.codexReset, .completed(.reset))
        XCTAssertEqual(try workspace.lines(in: workspace.consumeRequestsFile).count, 1)
    }

    @MainActor
    private func loadModel(
        executable: URL,
        timeout: Duration = .seconds(15),
        now: @escaping @MainActor () -> Date = { .now }
    ) async throws -> QuotaModel {
        let model = QuotaModel(
            codex: CodexQuotaSource(executableCandidates: [executable], timeout: timeout),
            claude: ScriptedQuotaSource([]),
            grok: ScriptedQuotaSource([]),
            now: now
        )
        model.refresh([.codex], force: true)
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertNotNil(model.statuses[.codex].latest?.snapshot)
        return model
    }
}
