import Foundation
import Observation

@MainActor
@Observable
final class GrokQuotaModel {
    enum State: Equatable {
        case loading
        case unavailable
        case available(GrokQuotaSnapshot)
    }

    private let quotaService: GrokQuotaService
    private let cooldown: Duration
    private var refreshAfter: ContinuousClock.Instant

    private(set) var state = State.loading
    private(set) var isRefreshing = false
    private(set) var refreshFailure: GrokQuotaUnavailability?

    init(quotaService: GrokQuotaService, cooldown: Duration = .seconds(60)) {
        self.quotaService = quotaService
        self.cooldown = cooldown
        refreshAfter = .now
    }

    /// Keeps the current state while fetching; a failed fetch leaves an earlier snapshot in place, marked stale.
    func refresh(force: Bool = false) {
        guard !isRefreshing, force || ContinuousClock.now >= refreshAfter else { return }
        isRefreshing = true
        Task {
            switch await quotaService.fetch() {
            case .success(let snapshot):
                state = .available(snapshot)
                refreshFailure = nil
            case .failure(let reason):
                refreshFailure = reason
                if state == .loading { state = .unavailable }
            }
            refreshAfter = .now + cooldown
            isRefreshing = false
        }
    }
}
