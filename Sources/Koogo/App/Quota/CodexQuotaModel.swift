import Foundation
import Observation

@MainActor
@Observable
final class CodexQuotaModel {
    enum State: Equatable {
        case loading
        case unavailable(CodexQuotaUnavailability)
        case available(CodexQuotaSnapshot)
    }

    enum ResetState: Equatable {
        case idle
        case confirming(CodexQuotaResetAttempt, failure: CodexQuotaResetFailure? = nil)
        case submitting
        case completed(CodexQuotaResetOutcome)
        /// The request may have reached the server; only a retry with the same attempt can settle it.
        case unconfirmed(CodexQuotaResetAttempt, CodexQuotaResetFailure)
    }

    private let quotaService: CodexQuotaService
    private let cooldown: Duration
    private var refreshAfter: ContinuousClock.Instant

    private(set) var state = State.loading
    private(set) var resetState = ResetState.idle
    private(set) var isRefreshing = false
    private(set) var refreshFailure: CodexQuotaUnavailability?

    var snapshot: CodexQuotaSnapshot? {
        guard case .available(let snapshot) = state else { return nil }
        return snapshot
    }

    var isResetting: Bool {
        if case .submitting = resetState { return true }
        return false
    }

    var canChooseReset: Bool {
        guard !isRefreshing, refreshFailure == nil else { return false }
        switch resetState {
        case .idle, .completed: return true
        case .confirming, .submitting, .unconfirmed: return false
        }
    }

    init(
        quotaService: CodexQuotaService,
        cooldown: Duration = .seconds(60)
    ) {
        self.quotaService = quotaService
        self.cooldown = cooldown
        refreshAfter = .now
    }

    func refresh(force: Bool = false) {
        guard !isRefreshing, !isResetting, force || ContinuousClock.now >= refreshAfter else { return }
        if case .unavailable = state { state = .loading }
        isRefreshing = true
        Task { await fetchQuota() }
    }

    func beginReset(creditID: String) {
        guard canChooseReset,
            let credit = snapshot?.account?.resetCredits?.credits?.first(where: { $0.id == creditID }),
            credit.canUse(at: .now)
        else { return }
        resetState = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancelReset() {
        guard case .confirming = resetState else { return }
        resetState = .idle
    }

    func submitReset() {
        guard !isRefreshing else { return }
        let attempt: CodexQuotaResetAttempt
        switch resetState {
        case .confirming(let pending, _), .unconfirmed(let pending, _):
            attempt = pending
        case .idle, .submitting, .completed:
            return
        }
        resetState = .submitting
        // The model owns this task, not the popover. Closing a view cannot cancel an irreversible write.
        Task {
            let result = await quotaService.consume(attempt)
            isRefreshing = true
            await fetchQuota()
            switch result {
            case .success(let outcome):
                resetState = .completed(outcome)
            case .failure(let failure) where attempt.writeStarted.withLock({ $0 }):
                resetState = .unconfirmed(attempt, failure)
            case .failure(let failure):
                resetState = .confirming(attempt, failure: failure)
            }
        }
    }

    /// Callers serialize reads with writes; a pre-reset read can never overwrite the post-reset snapshot.
    private func fetchQuota() async {
        switch await quotaService.fetch() {
        case .success(let snapshot):
            state = .available(snapshot)
            refreshFailure = nil
            if case .confirming(let attempt, _) = resetState,
                snapshot.account?.resetCredits?.credits?.contains(where: {
                    $0.id == attempt.credit.id && $0.canUse(at: .now)
                }) != true
            {
                resetState = .idle
            }
        case .failure(let reason):
            refreshFailure = reason
            if snapshot == nil { state = .unavailable(reason) }
        }
        refreshAfter = .now + cooldown
        isRefreshing = false
    }
}
