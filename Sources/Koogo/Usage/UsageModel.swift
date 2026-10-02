import Foundation
import Observation

@MainActor
@Observable
final class UsageModel {
    private let pipeline: UsagePipeline
    private let now: @MainActor () -> Date
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var queued: [Provider]?

    private(set) var snapshot: UsageSnapshot?

    init(pipeline: UsagePipeline, now: @escaping @MainActor () -> Date = { .now }) {
        self.pipeline = pipeline
        self.now = now
    }

    /// Rebuilds the snapshot for the given providers. A call during a refresh runs once that refresh ends.
    func refresh(providers: [Provider]) {
        guard !isRefreshing else {
            queued = providers
            return
        }
        let date = now()
        isRefreshing = true
        Task(priority: .utility) {
            snapshot = await pipeline.run(at: date, providers: providers).snapshot
            isRefreshing = false
            if let queued {
                self.queued = nil
                refresh(providers: queued)
            }
        }
    }
}
