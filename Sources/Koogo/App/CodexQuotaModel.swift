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
    private var refreshTask: Task<Void, Never>?

    private(set) var state = State.loading

    init(quotaService: CodexQuotaService) {
        self.quotaService = quotaService
    }

    func refresh() {
        guard refreshTask == nil else {
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
        }
    }
}
