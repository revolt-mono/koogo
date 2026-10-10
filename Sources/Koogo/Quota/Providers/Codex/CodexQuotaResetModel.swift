import Foundation
import Observation

/// Spends a banked reset on the user's confirmation. It reads Codex's limits from the quota model, writes through the same Codex tool, and holds Codex busy there through the write and the reread that makes the shown limits authoritative.
@MainActor
@Observable
final class CodexQuotaResetModel {
    private let quota: QuotaModel
    private var pending = CodexQuotaResetFlow.idle

    init(quota: QuotaModel) {
        self.quota = quota
    }

    var now: Date {
        quota.now()
    }

    var credits: QuotaSnapshot.ResetCredits? {
        quota.statuses[.codex].latest?.snapshot?.resetCredits
    }

    var isBusy: Bool {
        quota.isBusy(.codex)
    }

    /// A confirmation outlives its credit only until the next reading drops that credit.
    var flow: CodexQuotaResetFlow {
        pending.reconciled { usableCredit(id: $0.id) != nil }
    }

    var isShown: Bool {
        credits != nil || flow != .idle
    }

    var canChoose: Bool {
        guard !isBusy, case .available = quota.statuses[.codex].latest else { return false }
        return flow.acceptsChoice
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
