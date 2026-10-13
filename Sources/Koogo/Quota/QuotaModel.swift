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

/// The latest reading of every quota provider. One read per provider runs at a time; `read` is the only way in and out of the busy state.
@MainActor
@Observable
final class QuotaModel {
    let sources: QuotaSources
    /// Wall-clock time for deadlines in readings; the cooldown runs on the monotonic clock so a clock step cannot stretch or skip it.
    let now: @MainActor () -> Date

    private(set) var statuses = EnumMap<QuotaProvider, QuotaStatus> { _ in .unread }

    init(sources: QuotaSources = .production, now: @escaping @MainActor () -> Date = { .now }) {
        self.sources = sources
        self.now = now
    }

    func refresh(_ providers: some Sequence<QuotaProvider>) {
        let now = ContinuousClock.now
        reload(
            providers.filter { provider in
                guard case .read(let reading, let readAt) = statuses[provider] else { return true }
                return now >= readAt + Self.cooldown(after: reading)
            }
        )
    }

    /// Limits go stale after a minute. A login without a plan holds for a day, since only the user changes it. Failures are retried on the next refresh.
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
            read(provider) { await source.load() }
        }
    }

    /// Holds the provider busy while the work runs, then records its reading. Returns false, doing nothing, while a read is in flight. The work runs on the main actor, so state it settles lands together with the reading.
    @discardableResult
    func read(_ provider: QuotaProvider, _ work: @escaping @MainActor () async -> QuotaReading) -> Bool {
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
            statuses[provider] = .read(reading, since: .now)
        }
        return true
    }
}
