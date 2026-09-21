import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private let usageService: UsageService
    private let now: @MainActor () -> Date
    private var isRefreshing = false

    private(set) var snapshot: UsageSnapshot?

    init(
        usageService: UsageService,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.usageService = usageService
        self.now = now
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }
        let date = now()
        isRefreshing = true
        Task(priority: .utility) {
            defer {
                isRefreshing = false
            }
            snapshot = await usageService.refresh(at: date).snapshot
        }
    }
}
