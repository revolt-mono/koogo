import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private let usageService: UsageService
    private let now: @MainActor () -> Date
    private var refreshTask: Task<Void, Never>?

    private(set) var snapshot: UsageSnapshot?

    init(
        usageService: UsageService,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.usageService = usageService
        self.now = now
    }

    func refresh() {
        guard refreshTask == nil else {
            return
        }
        let date = now()
        refreshTask = Task(priority: .utility) { [usageService] in
            defer {
                refreshTask = nil
            }
            snapshot = await usageService.refresh(at: date).snapshot
        }
    }
}
