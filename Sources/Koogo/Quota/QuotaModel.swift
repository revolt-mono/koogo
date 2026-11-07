import Foundation
import Observation
import os

enum QuotaStatus: Equatable, Sendable {
    case unread
    case reading(last: QuotaReading?)
    case read(QuotaReading, since: ContinuousClock.Instant)

    var latest: QuotaReading? {
        switch self {
        case .unread: nil
        case .reading(let last): last
        case .read(let reading, _): reading
        }
    }

    var isBusy: Bool {
        if case .reading = self { true } else { false }
    }
}

/// app-scoped; refreshed by the app at launch and by the usage page on open. reads are single-flight per provider;
/// requests made during a read are dropped. a codex reset holds codex busy through submission and reread.
@MainActor
@Observable
final class QuotaModel {
    private let sources: QuotaSources
    let now: @MainActor () -> Date
    private let monotonicNow: @MainActor () -> ContinuousClock.Instant

    private(set) var statuses = EnumMap<QuotaProvider, QuotaStatus> { _ in .unread }
    private(set) var codexReset = CodexQuotaResetFlow.idle

    init(
        sources: QuotaSources,
        now: @escaping @MainActor () -> Date = { .now },
        monotonicNow: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.sources = sources
        self.now = now
        self.monotonicNow = monotonicNow
    }

    var codexResetCredits: QuotaSnapshot.ResetCredits? {
        statuses[.codex].latest?.snapshot?.resetCredits
    }

    func refresh(_ providers: [QuotaProvider]) {
        let now = monotonicNow()
        reload(
            providers.filter { provider in
                guard case .read(let reading, let readAt) = statuses[provider] else { return true }
                return now >= readAt + Self.cooldown(after: reading)
            }
        )
    }

    private static func cooldown(after reading: QuotaReading) -> Duration {
        switch reading {
        case .available: .seconds(60)
        case .unavailable(.noPlan): .seconds(24 * 60 * 60)
        case .unavailable: .zero
        }
    }

    func reload(_ providers: [QuotaProvider]) {
        for provider in providers where !statuses[provider].isBusy {
            let source = sources[provider]
            read(provider) { await source.load() }
        }
    }

    func canUseCodexReset(_ credit: QuotaSnapshot.ResetCredit) -> Bool {
        !statuses[.codex].isBusy && codexReset.acceptsChoice && credit.canUse(at: now())
    }

    func beginCodexReset(creditID: String) {
        guard let credit = codexCredit(id: creditID), canUseCodexReset(credit) else {
            return
        }
        codexReset = .confirming(CodexQuotaResetAttempt(credit: credit))
    }

    func cancelCodexReset() {
        guard case .confirming = codexReset else {
            return
        }
        codexReset = .idle
    }

    func submitCodexReset() {
        dropLapsedCodexConfirmation()
        guard !statuses[.codex].isBusy, let submission = codexReset.submission else {
            return
        }
        codexReset = .submitting
        let source = sources.codex
        read(.codex) {
            let result = await source.consume(submission.attempt)
            let reading = await source.load()
            self.codexReset = .settled(submission, result)
            return reading
        }
    }

    private func dropLapsedCodexConfirmation() {
        guard case .confirming(let attempt, _) = codexReset,
            codexCredit(id: attempt.credit.id)?.canUse(at: now()) != true
        else {
            return
        }
        codexReset = .idle
    }

    private func codexCredit(id: String) -> QuotaSnapshot.ResetCredit? {
        codexResetCredits?.credits?.first { $0.id == id }
    }

    private func read(_ provider: QuotaProvider, _ work: @escaping @MainActor () async -> QuotaReading) {
        statuses[provider] = .reading(last: statuses[provider].latest)
        Task {
            let reading = await work()
            let outcome =
                switch reading {
                case .available: "available"
                case .unavailable(let reason): "unavailable reason=\(reason.rawValue)"
                }
            Logger.quota.info("\(provider.rawValue, privacy: .public) fetch \(outcome, privacy: .public)")
            statuses[provider] = .read(reading, since: monotonicNow())
            if provider == .codex {
                dropLapsedCodexConfirmation()
            }
        }
    }
}
