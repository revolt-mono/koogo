import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaResetModelTests: XCTestCase {
    @MainActor
    func testConfirmationAndCancellationNeverSendAConsume() async throws {
        let source = ScriptedCodexResetSource(readings: [.available(snapshot())])
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }
        model.begin(creditID: "credit-a")
        XCTAssertEqual(model.flow, .confirming(attempt))
        model.cancel()
        model.submit()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    @MainActor
    func testConfirmationForACreditThatExpiresBeforeSubmitIsRefused() async throws {
        var now = Date.distantPast
        let source = ScriptedCodexResetSource(readings: [.available(snapshot())])
        let model = try await loadModels(source, now: { now }).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }

        now = try XCTUnwrap(attempt.credit.expiresAt)
        model.submit()
        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(source.consumed.withLock { $0 }, [])
    }

    @MainActor
    func testConsumeIsSingleFlightAndForcesAuthoritativeRefreshInsideCooldown() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .available(snapshot(usedPercent: 17, credits: []))],
            consumes: [.success(.reset)]
        )
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        model.submit()
        model.submit()
        model.begin(creditID: "credit-a")
        quota.refresh([.codex], force: true)
        guard case .submitting = model.flow else { return XCTFail("expected submitting") }
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .completed(.reset))
        let shown = try XCTUnwrap(quota.statuses[.codex].latest?.snapshot)
        XCTAssertEqual(shown.windows["Session"]?.usedPercent, 17)
        XCTAssertEqual(shown.resetCredits?.availableCount, 0)
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
        XCTAssertEqual(source.loads.withLock { $0 }, 2)
    }

    @MainActor
    func testSuccessfulConsumeAndFailedRefreshRemainSeparateAndRefreshCanRecover() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .unavailable(.sessionFailed), .available(snapshot(credits: []))],
            consumes: [.success(.reset)]
        )
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        model.submit()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .completed(.reset))
        XCTAssertEqual(quota.statuses[.codex].latest, .unavailable(.sessionFailed))
        XCTAssertFalse(model.canChoose)

        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.credits?.availableCount, 0)
        XCTAssertEqual(model.flow, .completed(.reset))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
    }

    @MainActor
    func testLostResponseKeepsIntentAcrossRefreshAndRetriesIdenticalRequest() async throws {
        let afterConsume = QuotaReading.available(snapshot(credits: []))
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), afterConsume, afterConsume, afterConsume],
            consumes: [.failure(.unconfirmed(.closed)), .success(.alreadyRedeemed)]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .closed))
        XCTAssertEqual(model.credits?.availableCount, 0)

        model.cancel()
        model.begin(creditID: "credit-b")
        model.refresh()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .closed))
        XCTAssertFalse(model.canChoose)
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt])

        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .completed(.alreadyRedeemed))
        XCTAssertEqual(source.consumed.withLock { $0 }, [attempt, attempt])
    }

    @MainActor
    func testTimeoutDoesNotAutomaticallyRetryOrDiscardIntent() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.unconfirmed(.timedOut))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .unconfirmed(attempt, .timedOut))
        XCTAssertEqual(source.consumed.withLock { $0.count }, 1)
        XCTAssertEqual(model.credits?.availableCount, 1)
    }

    @MainActor
    func testFailureBeforeTheWriteDropsTheConfirmationWithItsSnapshot() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .unavailable(.timedOut)],
            consumes: [.failure(.rejected(.timedOut))]
        )
        let (quota, model) = try await loadModels(source)
        model.begin(creditID: "credit-a")
        guard case .confirming = model.flow else { return XCTFail("expected confirmation") }
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(quota.statuses[.codex].latest, .unavailable(.timedOut))
        XCTAssertEqual(model.flow, .idle)
        XCTAssertFalse(model.canChoose)
    }

    @MainActor
    func testRejectedConsumeKeepsTheConfirmationWhileItsCreditSurvives() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .available(snapshot())],
            consumes: [.failure(.rejected(.rpc(code: -32601)))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }
        model.submit()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.flow, .confirming(attempt, rejection: .rpc(code: -32601)))
        XCTAssertFalse(model.canChoose)
    }

    @MainActor
    func testRejectedConsumeDropsConfirmationWhenReadRemovesCredit() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .available(snapshot(credits: []))],
            consumes: [.failure(.rejected(.closed))]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        model.submit()
        try await waitUntil { !model.isBusy }

        XCTAssertEqual(model.flow, .idle)
        XCTAssertEqual(model.credits?.availableCount, 0)
    }

    @MainActor
    func testRefreshInvalidatesConfirmationWhenCreditDisappears() async throws {
        for credits in [[], nil] as [[QuotaSnapshot.ResetCredit]?] {
            let source = ScriptedCodexResetSource(
                readings: [.available(snapshot()), .available(snapshot(credits: credits))]
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

    @MainActor
    func testPendingReadMustFinishBeforeConsumeCanStart() async throws {
        let source = ScriptedCodexResetSource(
            readings: [.available(snapshot()), .available(snapshot()), .available(snapshot())],
            consumes: [.success(.reset)]
        )
        let model = try await loadModels(source).reset
        model.begin(creditID: "credit-a")
        guard case .confirming(let attempt, _) = model.flow else { return XCTFail("expected confirmation") }
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

    /// A model pair whose first Codex reading has landed.
    @MainActor
    private func loadModels(
        _ source: ScriptedCodexResetSource,
        now: @escaping @MainActor () -> Date = { .now }
    ) async throws -> (quota: QuotaModel, reset: CodexQuotaResetModel) {
        let quota = makeQuotaModel(codex: source, now: now)
        let reset = CodexQuotaResetModel(quota: quota)
        quota.refresh([.codex], force: true)
        try await waitUntil { !quota.isBusy(.codex) }
        XCTAssertNotNil(quota.statuses[.codex].latest?.snapshot)
        return (quota, reset)
    }
}

private let creditA = QuotaSnapshot.ResetCredit(
    id: "credit-a",
    title: "Usage reset",
    expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
)

private func snapshot(
    usedPercent: Int = 25,
    credits: [QuotaSnapshot.ResetCredit]? = [creditA]
) -> QuotaSnapshot {
    QuotaSnapshot(
        windows: [QuotaWindow(title: "Session", usedPercent: Double(usedPercent), resetsAt: nil)],
        resetCredits: QuotaSnapshot.ResetCredits(availableCount: UInt64(credits?.count ?? 0), credits: credits)
    )!
}
