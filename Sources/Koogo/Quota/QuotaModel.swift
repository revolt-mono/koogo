import Foundation
import Observation

/// Where a provider's quota stands between reads. A cooldown exists only after an available reading.
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

    func isFresh(at now: ContinuousClock.Instant, within cooldown: Duration) -> Bool {
        guard case .read(.available, let readAt) = self else { return false }
        return now < readAt + cooldown
    }
}

/// The latest reading of every quota provider. One read per provider runs at a time; `read` is the only way in and out of the busy state.
@MainActor
@Observable
final class QuotaModel {
    private static let cooldown: Duration = .seconds(60)

    let sources: QuotaSources
    /// Wall-clock time for deadlines in readings; the cooldown runs on the monotonic clock so a clock step cannot stretch or skip it.
    let now: @MainActor () -> Date

    private(set) var statuses = EnumMap<QuotaProvider, QuotaStatus> { _ in .unread }

    init(sources: QuotaSources = .production, now: @escaping @MainActor () -> Date = { .now }) {
        self.sources = sources
        self.now = now
    }

    func isBusy(_ provider: QuotaProvider) -> Bool {
        statuses[provider].isBusy
    }

    /// Reads each provider whose reading is stale. `force` skips the cooldown but never doubles a read in flight.
    func refresh(_ providers: some Sequence<QuotaProvider>, force: Bool = false) {
        for provider in providers where force || !statuses[provider].isFresh(at: .now, within: Self.cooldown) {
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
            Telemetry.quota.info("\(provider.rawValue, privacy: .public) fetch \(outcome, privacy: .public)")
            statuses[provider] = .read(reading, since: .now)
        }
        return true
    }
}
