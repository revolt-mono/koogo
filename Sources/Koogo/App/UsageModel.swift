import Observation

@MainActor
@Observable
final class UsageModel {
    private let usageService: UsageService

    private(set) var snapshot: UsageSnapshot?

    init(usageService: UsageService) {
        self.usageService = usageService

        Task(priority: .utility) {
            await refresh()
        }
    }

    func refresh() async {
        snapshot = await usageService.refresh()
    }
}
