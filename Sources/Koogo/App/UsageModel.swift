import Observation

@MainActor
@Observable
final class UsageModel {
    private let usageService: UsageService
    private var refreshTask: Task<Void, Never>?

    private(set) var snapshot: UsageSnapshot?

    init(usageService: UsageService) {
        self.usageService = usageService
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else {
            return
        }
        refreshTask = Task(priority: .utility) { [usageService] in
            defer {
                refreshTask = nil
            }
            snapshot = await usageService.refresh()
        }
    }
}
