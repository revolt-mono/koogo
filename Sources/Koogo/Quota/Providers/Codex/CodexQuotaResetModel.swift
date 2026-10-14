import Foundation
import Observation

/// Spends a banked reset on the user's confirmation. It reads Codex's limits from the quota model, writes through the same Codex tool, and holds Codex busy there through the write and the reread that makes the shown limits authoritative.
@MainActor
@Observable
final class CodexQuotaResetModel {
    private let quota: QuotaModel
    private let clock: @MainActor () -> Date
    private var pending = CodexQuotaResetFlow.idle

    /// Credit expiry is judged on wall-clock time.
    init(quota: QuotaModel, now: @escaping @MainActor () -> Date = { .now }) {
        self.quota = quota
        clock = now
    }

    var now: Date {
        clock()
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
        let source = quota.sources.codex
        let started = quota.read(.codex) {
            let result = await source.consume(submission.attempt)
            let reading = await source.load()
            self.pending = .settled(submission, result)
            return reading
        }
        if started {
            pending = .submitting(submission)
        }
    }

    private func usableCredit(id: String) -> QuotaSnapshot.ResetCredit? {
        credits?.credits?.first { $0.id == id && $0.canUse(at: now) }
    }
}
