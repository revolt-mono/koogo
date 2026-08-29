import Observation

@MainActor
@Observable
final class CodexQuotaModel {
    enum State: Equatable {
        case loading
        case hidden
        case available(CodexQuotaSnapshot)
    }

    private let quotaService: CodexQuotaService
    private let refreshInterval: Duration
    private var refreshTask: Task<Void, Never>?
    private var refreshAfter: ContinuousClock.Instant

    private(set) var state = State.loading

    init(
        quotaService: CodexQuotaService,
        refreshInterval: Duration = .seconds(60)
    ) {
        self.quotaService = quotaService
        self.refreshInterval = refreshInterval
        refreshAfter = .now
    }

    func refresh() {
        guard refreshTask == nil, ContinuousClock.now >= refreshAfter else {
            return
        }
        if case .hidden = state {
            state = .loading
        }

        refreshTask = Task { [quotaService] in
            defer {
                refreshTask = nil
            }
            state = (await quotaService.fetch()).map(State.available) ?? .hidden
            refreshAfter = .now + refreshInterval
        }
    }
}
