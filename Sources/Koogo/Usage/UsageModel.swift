import Foundation
import Observation

/// app-scoped; refreshed by the app at launch and by the panel on open or provider changes.
@MainActor
@Observable
final class UsageModel {
    private let pipeline: UsagePipeline
    private let now: @MainActor () -> Date
    @ObservationIgnored private var state = RefreshState.idle

    private enum RefreshState {
        case idle
        case running(queued: [Provider]?)
    }

    private(set) var snapshot: UsageSnapshot?

    init(pipeline: UsagePipeline, now: @escaping @MainActor () -> Date) {
        self.pipeline = pipeline
        self.now = now
    }

    /// refreshes the requested providers; calls during a refresh queue another pass.
    func refresh(providers: [Provider]) {
        guard case .idle = state else {
            state = .running(queued: providers)
            return
        }
        let date = now()
        state = .running(queued: nil)
        Task(priority: .utility) {
            snapshot = await pipeline.run(at: date, providers: providers).snapshot
            let finished = state
            state = .idle
            if case .running(let queued?) = finished {
                refresh(providers: queued)
            }
        }
    }
}
