import Foundation
import Observation

@MainActor
@Observable
final class QuotaModel {
    private static let cooldown: Duration = .seconds(60)

    private let sources: EnumMap<QuotaProvider, any QuotaSource>
    private let codex: CodexQuotaSource
    private let now: @MainActor () -> Date
    private var pendingCodexReset = CodexQuotaResetFlow.idle

    private(set) var statuses = EnumMap<QuotaProvider, QuotaStatus> { _ in .unread }

    init(
        codex: CodexQuotaSource = CodexQuotaSource(),
        claude: any QuotaSource = ClaudeQuotaSource(),
        grok: any QuotaSource = GrokQuotaSource(),
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        sources = EnumMap(codex: codex, claude: claude, grok: grok)
        self.codex = codex
        self.now = now
    }

    func isBusy(_ provider: QuotaProvider) -> Bool {
        statuses[provider].isBusy
    }

    func refresh(_ providers: some Sequence<QuotaProvider>, force: Bool = false) {
        for provider in providers {
            let status = statuses[provider]
            guard !status.isBusy, force || !status.isFresh(at: .now, within: Self.cooldown) else { continue }
            statuses[provider] = .reading(last: status.latest)
            Task { settle(provider, with: await sources[provider].load()) }
        }
    }

    private func settle(_ provider: QuotaProvider, with reading: QuotaReading) {
        switch reading {
        case .available:
            Telemetry.quota.info("\(provider.rawValue, privacy: .public) fetch available")
        case .unavailable(let reason):
            Telemetry.quota.info(
                "\(provider.rawValue, privacy: .public) fetch unavailable reason=\(reason.rawValue, privacy: .public)"
            )
        }
        statuses[provider] = .read(reading, since: .now)
    }

    // MARK: Codex banked resets

    var codexResetCredits: QuotaSnapshot.ResetCredits? {
        statuses[.codex].latest?.snapshot?.resetCredits
    }

    /// A confirmation outlives its credit only until the next reading drops that credit.
    var codexReset: CodexQuotaResetFlow {
        if case .confirming(let attempt, _) = pendingCodexReset, usableCodexCredit(id: attempt.credit.id) == nil {
            return .idle
        }
        return pendingCodexReset
    }

    var canChooseCodexReset: Bool {
        guard !isBusy(.codex), case .available = statuses[.codex].latest else { return false }
        switch codexReset {
        case .idle, .completed: return true
        case .confirming, .submitting, .unconfirmed: return false
        }
    }

    func beginCodexReset(creditID: String) {
        guard canChooseCodexReset, let credit = usableCodexCredit(id: creditID) else { return }
        pendingCodexReset = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancelCodexReset() {
        guard case .confirming = codexReset else { return }
        pendingCodexReset = .idle
    }

    /// Consumes the confirmed credit, then rereads the account so the shown limits are authoritative.
    func submitCodexReset() {
        let attempt: CodexQuotaResetAttempt
        let retryingUnconfirmed: Bool
        switch codexReset {
        case .confirming(let pending, _):
            (attempt, retryingUnconfirmed) = (pending, false)
        case .unconfirmed(let pending, _):
            (attempt, retryingUnconfirmed) = (pending, true)
        case .idle, .submitting, .completed:
            return
        }
        guard !isBusy(.codex) else { return }
        pendingCodexReset = .submitting(attempt, retryingUnconfirmed: retryingUnconfirmed)
        statuses[.codex] = .reading(last: statuses[.codex].latest)
        Task {
            let result = await codex.consume(attempt)
            settle(.codex, with: await codex.load())
            pendingCodexReset =
                switch result {
                case .success(let outcome): .completed(outcome)
                case .failure(.unconfirmed(let failure)): .unconfirmed(attempt, failure)
                case .failure(.rejected(let failure)) where retryingUnconfirmed: .unconfirmed(attempt, failure)
                case .failure(.rejected(let failure)): .confirming(attempt, rejection: failure)
                }
        }
    }

    private func usableCodexCredit(id: String) -> QuotaSnapshot.ResetCredit? {
        codexResetCredits?.credits?.first { $0.id == id && $0.canUse(at: now()) }
    }
}
