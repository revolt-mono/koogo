import Foundation
import Observation

/// One user-confirmed reset. A retry reuses the same credit and key so the server can dedupe it.
struct CodexQuotaResetAttempt: Equatable, Sendable {
    let credit: QuotaSnapshot.ResetCredit
    let idempotencyKey = UUID()
}

enum CodexQuotaResetOutcome: String, Decodable, Sendable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
}

typealias CodexQuotaResetResult = Result<CodexQuotaResetOutcome, CodexAppServer.CallError>

/// The intent to spend one banked Codex reset, from confirmation through the server's answer. The quota
/// model serializes the consume against reads and re-reads the quota after it.
@MainActor
@Observable
final class CodexQuotaResetModel {
    enum State: Equatable {
        case idle
        case confirming(CodexQuotaResetAttempt, failure: CodexAppServer.Failure? = nil)
        case submitting
        case completed(CodexQuotaResetOutcome)
        /// The request may have reached the server; only a retry with the same attempt can settle it.
        case unconfirmed(CodexQuotaResetAttempt, CodexAppServer.Failure)
    }

    private let quotaModel: QuotaModel
    private let source: CodexQuotaSource
    private let now: @MainActor () -> Date
    private var pending = State.idle

    /// A confirmation holds only while the latest snapshot still offers its credit unexpired. An
    /// unconfirmed attempt outlives any refresh, since only its own retry can settle it.
    var state: State {
        if case .confirming(let attempt, _) = pending, usableCredit(id: attempt.credit.id) == nil {
            return .idle
        }
        return pending
    }

    var quota: QuotaState? { quotaModel.states[.codex] }
    var resetCredits: QuotaSnapshot.ResetCredits? { quota?.snapshot?.resetCredits }

    /// A read or a consume is in flight; neither starts while the other runs.
    var isBusy: Bool { quotaModel.isBusy(.codex) }

    var canChooseReset: Bool {
        guard !isBusy, case .available(_, stale: nil) = quota else { return false }
        switch state {
        case .idle, .completed: return true
        case .confirming, .submitting, .unconfirmed: return false
        }
    }

    init(quotaModel: QuotaModel, source: CodexQuotaSource, now: @escaping @MainActor () -> Date = { .now }) {
        self.quotaModel = quotaModel
        self.source = source
        self.now = now
    }

    func refresh() {
        quotaModel.refresh(.codex, force: true)
    }

    func beginReset(creditID: String) {
        guard canChooseReset, let credit = usableCredit(id: creditID) else { return }
        pending = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancelReset() {
        guard case .confirming = state else { return }
        pending = .idle
    }

    func submitReset() {
        let attempt: CodexQuotaResetAttempt
        switch state {
        case .confirming(let pending, _), .unconfirmed(let pending, _):
            attempt = pending
        case .idle, .submitting, .completed:
            return
        }
        // The quota model owns the consume; closing a view cannot cancel an irreversible write.
        let source = source
        guard let consume = quotaModel.write(to: .codex, { await source.consume(attempt) }) else { return }
        let wasUnconfirmed = if case .unconfirmed = state { true } else { false }
        pending = .submitting
        Task {
            switch await consume.value {
            case .success(let outcome):
                pending = .completed(outcome)
            case .failure(.unconfirmed(let failure)):
                pending = .unconfirmed(attempt, failure)
            case .failure(.rejected(let failure)):
                // An earlier attempt may already have reached the server; a rejected retry cannot clear that.
                pending = wasUnconfirmed ? .unconfirmed(attempt, failure) : .confirming(attempt, failure: failure)
            }
        }
    }

    private func usableCredit(id: String) -> QuotaSnapshot.ResetCredit? {
        resetCredits?.credits?.first { $0.id == id && $0.canUse(at: now()) }
    }
}
