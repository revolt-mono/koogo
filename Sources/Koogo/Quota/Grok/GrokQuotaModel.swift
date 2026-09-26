import Observation

@MainActor
@Observable
final class GrokQuotaModel {
    private static let cooldown: Duration = .seconds(60)

    private let quotaService: GrokQuotaService
    private var refreshAfter = ContinuousClock.now

    private(set) var state: QuotaState<GrokQuotaSnapshot, GrokQuotaUnavailability> = .loading
    private(set) var isRefreshing = false

    init(quotaService: GrokQuotaService) {
        self.quotaService = quotaService
    }

    /// Keeps the current state while fetching.
    func refresh(force: Bool = false) {
        guard !isRefreshing, force || ContinuousClock.now >= refreshAfter else { return }
        isRefreshing = true
        Task {
            state.apply(await quotaService.fetch())
            refreshAfter = .now + Self.cooldown
            isRefreshing = false
        }
    }
}
