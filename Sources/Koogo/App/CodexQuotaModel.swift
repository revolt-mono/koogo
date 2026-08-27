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

        refreshTask = Task { [weak self, quotaService] in
            guard let self else {
                return
            }
            defer {
                refreshTask = nil
            }
            if let snapshot = await quotaService.fetch() {
                state = .available(snapshot)
            } else {
                state = .hidden
            }
        }
    }
}
