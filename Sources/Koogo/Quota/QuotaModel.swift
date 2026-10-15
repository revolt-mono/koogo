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

/// app-scoped; refreshed by the app at launch and by the panel on open. reads are serialized per provider.
@MainActor
@Observable
final class QuotaModel {
    private let sources: QuotaSources
    private let monotonicNow: @MainActor () -> ContinuousClock.Instant

    private(set) var statuses = EnumMap<QuotaProvider, QuotaStatus> { _ in .unread }

    init(sources: QuotaSources = .production, now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) {
        self.sources = sources
        self.monotonicNow = now
    }

    func refresh(_ providers: some Sequence<QuotaProvider>) {
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

    func reload(_ providers: some Sequence<QuotaProvider>) {
        for provider in providers {
            let source = sources[provider]
            _ = read(provider) { await source.load() }
        }
    }

    /// returns false while codex is busy; settles the reset result and refreshed limits in one busy span.
    func resetCodex(
        _ attempt: CodexQuotaResetAttempt,
        settle: @escaping @MainActor (CodexQuotaResetResult) -> Void
    ) -> Bool {
        let source = sources.codex
        return read(.codex) {
            let result = await source.consume(attempt)
            let reading = await source.load()
            settle(result)
            return reading
        }
    }

    private func read(_ provider: QuotaProvider, _ work: @escaping @MainActor () async -> QuotaReading) -> Bool {
        guard !statuses[provider].isBusy else {
            return false
        }
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
        }
        return true
    }
}
