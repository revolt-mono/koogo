import XCTest

@testable import Koogo

@MainActor
final class CodexQuotaResetModelTests: XCTestCase {
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let source = ScriptedQuotaSource([.available(snapshot())])
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)
        model.begin(creditID: "credit-a")
        XCTAssertEqual(model.flow, .confirming(attempt))
        model.cancel()
        model.submit()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    func testConfirmationForACreditThatExpiresBeforeSubmitIsRefused() async throws {
        var now = Date.distantPast
        let source = ScriptedQuotaSource([.available(snapshot())])
        let model = try await loadModels(source, now: { now }).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)

        now = try XCTUnwrap(attempt.credit.expiresAt)
        model.submit()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    func testConsumeIsSingleFlightAndForcesAuthoritativeRefreshInsideCooldown() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot(usedPercent: 17, credits: []))],
            consumes: [.success(.reset)]
        )
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        model.submit()
        model.submit()
        model.begin(creditID: "credit-a")
        quota.reload([.codex])
        XCTAssertEqual(model.flow, .submitting)
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .completed(.reset))
        let shown = try XCTUnwrap(quota.statuses[.codex].latest?.snapshot)
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
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        model.submit()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .completed(.reset))
        XCTAssertEqual(quota.statuses[.codex].latest, .unavailable(.sessionFailed))

        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.resetCredits?.availableCount, 0)
        XCTAssertEqual(model.flow, .completed(.reset))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
    }

    func testLostResponseKeepsIntentAcrossRefreshAndRetriesIdenticalRequest() async throws {
        let afterConsume = QuotaReading.available(snapshot(credits: []))
        let source = ScriptedQuotaSource(
            [.available(snapshot()), afterConsume, afterConsume, afterConsume],
            consumes: [.failure(.unconfirmed(.closed)), .success(.alreadyRedeemed)]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .closed))
        XCTAssertEqual(model.resetCredits?.availableCount, 0)

        model.cancel()
        model.begin(creditID: "credit-b")
        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .closed))
        model.begin(creditID: "credit-a")
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .closed))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt])

        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .completed(.alreadyRedeemed))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt, attempt])
    }

    func testTimeoutDoesNotAutomaticallyRetryOrDiscardIntent() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.unconfirmed(.timedOut))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .timedOut))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
        XCTAssertEqual(model.resetCredits?.availableCount, 1)
    }

    func testFailureBeforeTheWriteDropsTheConfirmationWithItsSnapshot() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .unavailable(.timedOut)],
            consumes: [.failure(.rejected(.timedOut))]
        )
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        guard case .confirming = model.flow else { return XCTFail("expected confirmation") }
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(quota.statuses[.codex].latest, .unavailable(.timedOut))
        XCTAssertEqual(model.flow, .idle)
        model.begin(creditID: "credit-a")
        XCTAssertEqual(model.flow, .idle, "a failed reread leaves no credit to choose")
    }

    func testRejectedConsumeKeepsTheConfirmationWhileItsCreditSurvives() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.rejected(.rpc(code: -32601)))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .confirming(attempt, rejection: .rpc(code: -32601)))
        model.begin(creditID: "credit-a")
        XCTAssertEqual(model.flow, .confirming(attempt, rejection: .rpc(code: -32601)))
    }

    func testRejectedConsumeDropsConfirmationWhenReadRemovesCredit() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot(credits: []))],
            consumes: [.failure(.rejected(.closed))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        model.submit()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.resetCredits?.availableCount, 0)
    }

    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        for credits in [[], nil] as [[QuotaSnapshot.ResetCredit]?] {
            let source = ScriptedQuotaSource(
                [.available(snapshot()), .available(snapshot(credits: credits))]
            )
            let model = try await loadModels(source).reset
            model.begin(creditID: "credit-a")
            model.refresh()
            try await waitUntil { !model.isBusy }
            XCTAssertEqual(model.flow, .idle)
            model.submit()
            XCTAssertEqual(source.consumed.withLock { $0 }, [])
        }
    }

    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let source = ScriptedQuotaSource(
            [.available(snapshot()), .available(snapshot()), .available(snapshot())],
            consumes: [.success(.reset)]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        let attempt = try XCTUnwrap(model.flow.confirmingAttempt)
        model.refresh()
        model.submit()
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.flow, .confirming(attempt))
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .completed(.reset))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt])
    }

    private func loadModels(
        _ source: ScriptedQuotaSource,
        now: @escaping @MainActor () -> Date = { .now }
    ) async throws -> (quota: QuotaModel, reset: CodexQuotaResetModel) {
        let quota = makeQuotaModel(codex: source)
        let reset = CodexQuotaResetModel(quota: quota, now: now)
        quota.reload([.codex])
        try await waitUntil { !quota.statuses[.codex].isBusy }
        XCTAssertNotNil(quota.statuses[.codex].latest?.snapshot)
        return (quota, reset)
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
