import Observation

protocol QuotaService: Sendable {
    associatedtype Snapshot: Equatable
    associatedtype Reason: Error & Equatable

    func fetch() async -> Result<Snapshot, Reason>
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
