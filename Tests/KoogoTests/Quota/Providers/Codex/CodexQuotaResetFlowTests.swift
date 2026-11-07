import XCTest

@testable import Koogo

@MainActor
final class CodexQuotaResetFlowTests: XCTestCase {
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let source = ScriptedQuotaSource([.available(snapshot())])
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)
        model.beginCodexReset(creditID: "credit-a")
        XCTAssertEqual(model.codexReset, .confirming(attempt))
        model.cancelCodexReset()
        model.submitCodexReset()
        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    func testConfirmationForACreditThatExpiresBeforeSubmitIsRefused() async throws {
        var now = Date.distantPast
        let source = ScriptedQuotaSource([.available(snapshot())])
        let model = try await loadModel(source, now: { now })
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)

        now = try XCTUnwrap(attempt.credit.expiresAt)
        model.submitCodexReset()
        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    func testConsumeIsSingleFlightAndForcesAuthoritativeRefreshInsideCooldown() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot(usedPercent: 17, credits: []))],
            consumes: [.success(.reset)]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        model.submitCodexReset()
        model.submitCodexReset()
        model.beginCodexReset(creditID: "credit-a")
        model.reload([.codex])
        XCTAssertEqual(model.codexReset, .submitting)
        try await waitUntil { !model.statuses[.codex].isBusy }

        XCTAssertEqual(model.codexReset, .completed(.reset))
        let shown = try XCTUnwrap(model.statuses[.codex].latest?.snapshot)
        XCTAssertEqual(shown.windows["Session"]?.usedPercent, 17)
        XCTAssertEqual(shown.resetCredits?.availableCount, 0)
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
        XCTAssertEqual(source.loads.withLock { $0 }, 2)
    }

    func testSuccessfulConsumeAndFailedRefreshRemainSeparateAndRefreshCanRecover() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .unavailable(.sessionFailed), .available(snapshot(credits: []))],
            consumes: [.success(.reset)]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }

        XCTAssertEqual(model.codexReset, .completed(.reset))
        XCTAssertEqual(model.statuses[.codex].latest, .unavailable(.sessionFailed))

        model.reload([.codex])
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexResetCredits?.availableCount, 0)
        XCTAssertEqual(model.codexReset, .completed(.reset))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
    }

    func testLostResponseKeepsIntentAcrossRefreshAndRetriesIdenticalRequest() async throws {
        let afterConsume = QuotaReading.available(snapshot(credits: []))
        let source = ScriptedQuotaSource(
            [.available(snapshot()), afterConsume, afterConsume, afterConsume],
            consumes: [.failure(.unconfirmed(.closed)), .success(.alreadyRedeemed)]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .closed))
        XCTAssertEqual(model.codexResetCredits?.availableCount, 0)

        model.cancelCodexReset()
        model.beginCodexReset(creditID: "credit-b")
        model.reload([.codex])
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .closed))
        model.beginCodexReset(creditID: "credit-a")
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .closed))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt])

        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .completed(.alreadyRedeemed))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt, attempt])
    }

    func testTimeoutDoesNotAutomaticallyRetryOrDiscardIntent() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.unconfirmed(.timedOut))]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .unconfirmed(attempt, .timedOut))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
        XCTAssertEqual(model.codexResetCredits?.availableCount, 1)
    }

    func testFailureBeforeTheWriteDropsTheConfirmationWithItsSnapshot() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .unavailable(.timedOut), .available(snapshot())],
            consumes: [.failure(.rejected(.timedOut))]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        guard case .confirming = model.codexReset else { return XCTFail("expected confirmation") }
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.statuses[.codex].latest, .unavailable(.timedOut))
        XCTAssertEqual(model.codexReset, .idle)
        model.beginCodexReset(creditID: "credit-a")
        XCTAssertEqual(model.codexReset, .idle, "a failed reread leaves no credit to choose")

        model.reload([.codex])
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexResetCredits?.availableCount, 1)
        XCTAssertEqual(model.codexReset, .idle, "a read that restores the credit doesn't revive the confirmation")
    }

    func testRejectedConsumeKeepsTheConfirmationWhileItsCreditSurvives() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.rejected(.rpc(code: -32601)))]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .confirming(attempt, rejection: .rpc(code: -32601)))
        model.beginCodexReset(creditID: "credit-a")
        XCTAssertEqual(model.codexReset, .confirming(attempt, rejection: .rpc(code: -32601)))
    }

    func testRejectedConsumeDropsConfirmationWhenReadRemovesCredit() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot(credits: []))],
            consumes: [.failure(.rejected(.closed))]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }

        XCTAssertEqual(model.codexReset, .idle)
        XCTAssertEqual(model.codexResetCredits?.availableCount, 0)
    }

    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        for credits in [[], nil] as [[QuotaSnapshot.ResetCredit]?] {
            let source = ScriptedQuotaSource(
                [.available(snapshot()), .available(snapshot(credits: credits))]
            )
            let model = try await loadModel(source)
            model.beginCodexReset(creditID: "credit-a")
            model.reload([.codex])
            try await waitUntil { !model.statuses[.codex].isBusy }
            XCTAssertEqual(model.codexReset, .idle)
            model.submitCodexReset()
            XCTAssertEqual(source.consumed.withLock { $0 }, [])
        }
    }

    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot()), .available(snapshot())],
            consumes: [.success(.reset)]
        )
        let model = try await loadModel(source)
        model.beginCodexReset(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.codexReset.confirmingAttempt)
        model.reload([.codex])
        model.submitCodexReset()
        XCTAssertTrue(model.statuses[.codex].isBusy)
        XCTAssertEqual(model.codexReset, .confirming(attempt))
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
        model.submitCodexReset()
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertEqual(model.codexReset, .completed(.reset))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt])
    }

    private func loadModel(
        _ source: ScriptedQuotaSource,
        now: @escaping @MainActor () -> Date = { .now }
    ) async throws -> QuotaModel {
        let model = makeQuotaModel(codex: source, now: now)
        model.reload([.codex])
        try await waitUntil { !model.statuses[.codex].isBusy }
        XCTAssertNotNil(model.codexResetCredits)
        return model
    }
}

private func snapshot(
    usedPercent: Int = 25,
    credits: [QuotaSnapshot.ResetCredit]? = [.stub]
) -> QuotaSnapshot {
    QuotaSnapshot(
        windows: [QuotaWindow(title: "Session", usedPercent: Double(usedPercent), resetsAt: nil)],
        resetCredits: QuotaSnapshot.ResetCredits(availableCount: UInt64(credits?.count ?? 0), credits: credits)
    )!
}

extension CodexQuotaResetFlow {
    fileprivate var confirmingAttempt: CodexQuotaResetAttempt? {
        guard case .confirming(let attempt, _) = self else {
            return nil
        }
        return attempt
    }
}
