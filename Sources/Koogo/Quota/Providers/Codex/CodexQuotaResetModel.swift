import Foundation
import Observation

/// app-scoped; user confirmation starts a reset through the quota model, which stays busy through submission and reread.
@MainActor
@Observable
final class CodexQuotaResetModel {
    private let quota: QuotaModel
    private let wallClockNow: @MainActor () -> Date
    private var pending = CodexQuotaResetFlow.idle

    init(quota: QuotaModel, now: @escaping @MainActor () -> Date = { .now }) {
        self.quota = quota
        wallClockNow = now
    }

    var now: Date {
        wallClockNow()
    }

    var credits: QuotaSnapshot.ResetCredits? {
        quota.statuses[.codex].latest?.snapshot?.resetCredits
    }

    var isBusy: Bool {
        quota.statuses[.codex].isBusy
    }

    var flow: CodexQuotaResetFlow {
        if case .confirming(let attempt, _) = pending, usableCredit(id: attempt.credit.id) == nil {
            return .idle
        }
        return pending
    }

    var hasResetActivity: Bool {
        credits != nil || flow != .idle
    }

    private var canChoose: Bool {
        !isBusy && flow.acceptsChoice
    }

    func canUse(_ credit: QuotaSnapshot.ResetCredit) -> Bool {
        canChoose && credit.canUse(at: now)
    }

    func refresh() {
        quota.reload([.codex])
    }

    func begin(creditID: String) {
        guard canChoose, let credit = usableCredit(id: creditID) else { return }
        pending = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancel() {
        guard case .confirming = flow else { return }
        pending = .idle
    }

    func submit() {
        guard let submission = flow.submission else { return }
        let started = quota.resetCodex(submission.attempt) { result in
            self.pending = .settled(submission, result)
        }
        if started {
            pending = .submitting(submission)
        }
    }

    private func usableCredit(id: String) -> QuotaSnapshot.ResetCredit? {
        credits?.credits?.first { $0.id == id && $0.canUse(at: now) }
    }
}
