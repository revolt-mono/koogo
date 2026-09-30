import Foundation

struct UsageEventIndex: Sendable {
    private(set) var historyStart: Date
    private var events: [UsageEvent.Key: UsageEvent.Value] = [:]
    private var unpricedModels: [String: Date] = [:]

    init(since historyStart: Date) {
        self.historyStart = historyStart
    }

    var unpricedModelIDs: [String] {
        unpricedModels.keys.sorted()
    }

    var values: some Collection<UsageEvent> {
        events.lazy.map { UsageEvent(key: $0.key, value: $0.value) }
    }

    var keys: some Collection<UsageEvent.Key> {
        events.keys
    }

    var count: Int {
        events.count
    }

    mutating func insert(_ outcome: UsageLineOutcome) {
        guard outcome.timestamp >= historyStart else {
            return
        }
        switch outcome {
        case .event(let event):
            if let existing = events[event.key], !event.value.supersedes(existing) {
                return
            }
            events[event.key] = event.value
        case .unpricedModel(let id, let timestamp):
            unpricedModels[id] = max(unpricedModels[id] ?? .distantPast, timestamp)
        }
    }

    mutating func discard(before historyStart: Date) {
        self.historyStart = historyStart
        events = events.filter { $0.value.usage.timestamp >= historyStart }
        unpricedModels = unpricedModels.filter { $0.value >= historyStart }
    }
}
