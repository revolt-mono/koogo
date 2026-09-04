import Observation

@MainActor
@Observable
final class CodexQuotaModel {
    enum State: Equatable {
        case loading
        case unavailable(CodexQuotaUnavailability)
        case available(CodexQuotaSnapshot)
    }

    private let quotaService: CodexQuotaService
    private let cooldown: Duration
    private var isRefreshing = false
    private var refreshAfter: ContinuousClock.Instant

    private(set) var state = State.loading

    init(
        quotaService: CodexQuotaService,
        cooldown: Duration = .seconds(60)
    ) {
        self.quotaService = quotaService
        self.cooldown = cooldown
        refreshAfter = .now
    }

    func refresh() {
        guard !isRefreshing, ContinuousClock.now >= refreshAfter else {
            return
        }
        if case .unavailable = state {
            state = .loading
        }

        isRefreshing = true
        Task {
            defer {
                isRefreshing = false
            }
            switch await quotaService.fetch() {
            case .success(let snapshot):
                state = .available(snapshot)
            case .failure(let reason):
                state = .unavailable(reason)
            }
            refreshAfter = .now + cooldown
        }
    }
}
