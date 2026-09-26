import Foundation
import Observation

@MainActor
@Observable
final class CodexQuotaModel {
    enum ResetState: Equatable {
        case idle
        case confirming(CodexQuotaResetAttempt, failure: CodexAppServer.Failure? = nil)
        case submitting
        case completed(CodexQuotaResetOutcome)
        /// The request may have reached the server; only a retry with the same attempt can settle it.
        case unconfirmed(CodexQuotaResetAttempt, CodexAppServer.Failure)
    }

    private static let cooldown: Duration = .seconds(60)

    private let quotaService: CodexQuotaService
    private let now: @MainActor () -> Date
    private var refreshAfter = ContinuousClock.now
    private var isRefreshing = false

    private(set) var state: QuotaState<CodexQuotaSnapshot, CodexQuotaUnavailability> = .loading
    private(set) var resetState = ResetState.idle

    var snapshot: CodexQuotaSnapshot? { state.snapshot }

    /// A read or a consume is in flight. Neither starts while the other runs, so a pre-reset read
    /// can never overwrite the post-reset snapshot.
    var isBusy: Bool { isRefreshing || resetState == .submitting }

    var canChooseReset: Bool {
        guard !isBusy, case .available(_, stale: nil) = state else { return false }
        switch resetState {
        case .idle, .completed: return true
        case .confirming, .submitting, .unconfirmed: return false
        }
    }

    init(quotaService: CodexQuotaService, now: @escaping @MainActor () -> Date = { .now }) {
        self.quotaService = quotaService
        self.now = now
    }

    /// Keeps the current state while fetching.
    func refresh(force: Bool = false) {
        guard !isBusy, force || ContinuousClock.now >= refreshAfter else { return }
        isRefreshing = true
        Task { await fetchQuota() }
    }

    func beginReset(creditID: String) {
        guard canChooseReset, let credit = usableCredit(id: creditID) else { return }
        resetState = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancelReset() {
        guard case .confirming = resetState else { return }
        resetState = .idle
    }

    func submitReset() {
        guard !isBusy else { return }
        dropUnusableConfirmation()
        let attempt: CodexQuotaResetAttempt
        switch resetState {
        case .confirming(let pending, _), .unconfirmed(let pending, _):
            attempt = pending
        case .idle, .submitting, .completed:
            return
        }
        let wasUnconfirmed = if case .unconfirmed = resetState { true } else { false }
        resetState = .submitting
        // The model owns this task, not the popover. Closing a view cannot cancel an irreversible write.
        Task {
            let result = await quotaService.consume(attempt)
            await fetchQuota()
            switch result {
            case .completed(let outcome):
                resetState = .completed(outcome)
            case .unconfirmed(let failure):
                resetState = .unconfirmed(attempt, failure)
            case .rejected(let failure):
                // An earlier attempt may already have reached the server; a rejected retry cannot clear that.
                resetState = wasUnconfirmed ? .unconfirmed(attempt, failure) : .confirming(attempt, failure: failure)
            }
            dropUnusableConfirmation()
        }
    }

    /// Callers serialize reads with writes through `isBusy`.
    private func fetchQuota() async {
        state.apply(await quotaService.fetch())
        dropUnusableConfirmation()
        refreshAfter = .now + Self.cooldown
        isRefreshing = false
    }

    /// A confirmation is valid only for a credit the latest snapshot still offers unexpired. An
    /// unconfirmed attempt is kept, since only its own retry can settle it.
    private func dropUnusableConfirmation() {
        if case .confirming(let attempt, _) = resetState, usableCredit(id: attempt.credit.id) == nil {
            resetState = .idle
        }
    }

    private func usableCredit(id: String) -> CodexQuotaSnapshot.ResetCredit? {
        snapshot?.account?.resetCredits?.credits?.first { $0.id == id && $0.canUse(at: now()) }
    }
}
