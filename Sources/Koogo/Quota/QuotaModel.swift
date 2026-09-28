import Observation

protocol QuotaService: Sendable {
    associatedtype Snapshot: Equatable & Sendable & Encodable
    associatedtype Reason: Error & Equatable & RawRepresentable<String> & Encodable

    /// Names the provider in telemetry.
    static var name: String { get }

    /// Reads the quota once; callers use `fetch()`, which also records the outcome.
    func load() async -> Result<Snapshot, Reason>
}

extension QuotaService {
    @concurrent
    func fetch() async -> Result<Snapshot, Reason> {
        let result = await load()
        switch result {
        case .success:
            Telemetry.quota.info("\(Self.name, privacy: .public) fetch available")
        case .failure(let reason):
            Telemetry.quota.info(
                "\(Self.name, privacy: .public) fetch unavailable reason=\(reason.rawValue, privacy: .public)"
            )
        }
        return result
    }
}

/// Fetches one provider's quota on demand, coalescing overlapping refreshes and holding a cooldown
/// between successive fetches.
@MainActor
@Observable
final class QuotaModel<Service: QuotaService> {
    private let quotaService: Service
    private var refreshAfter = ContinuousClock.now

    private(set) var state: QuotaState<Service.Snapshot, Service.Reason> = .loading
    private(set) var isRefreshing = false

    init(quotaService: Service) {
        self.quotaService = quotaService
    }

    /// Keeps the current state while fetching.
    func refresh(force: Bool = false) {
        guard !isRefreshing, force || ContinuousClock.now >= refreshAfter else { return }
        isRefreshing = true
        Task {
            state.apply(await quotaService.fetch())
            refreshAfter = .now + .seconds(60)
            isRefreshing = false
        }
    }
}
