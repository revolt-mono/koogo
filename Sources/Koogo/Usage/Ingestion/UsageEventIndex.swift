import Foundation

/// Deduplicated events inside one history window. Every insert and merge keeps
/// one event per key, replacing it only when `UsageEvent.Value.supersedes` says so.
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

    var count: Int {
        events.count
    }

    mutating func reserveCapacity(_ minimumCapacity: Int) {
        events.reserveCapacity(minimumCapacity)
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

    mutating func merge(_ other: Self) {
        events.merge(other.events) { current, candidate in
            candidate.supersedes(current) ? candidate : current
        }
        unpricedModels.merge(other.unpricedModels) { current, candidate in max(current, candidate) }
    }

    mutating func discard(before historyStart: Date) {
        self.historyStart = historyStart
        events = events.filter { $0.value.usage.timestamp >= historyStart }
        unpricedModels = unpricedModels.filter { $0.value >= historyStart }
    }
}
