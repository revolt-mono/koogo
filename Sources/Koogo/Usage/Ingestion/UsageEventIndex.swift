import Foundation

/// The surviving copy of every request id seen in one log, or across logs.
struct UsageEventIndex: Sendable {
    private struct Stored: Sendable {
        let record: UsageRecord
        let revision: UsageEvent.Revision
    }

    private var events: [UsageEventID: Stored] = [:]

    init() {}

    /// An index of events with distinct ids that already lie inside the window.
    init(distinct events: some Sequence<UsageEvent>) {
        for event in events {
            insert(event, since: .distantPast)
        }
    }

    var values: some Collection<UsageEvent> {
        events.lazy.map { UsageEvent(id: $0.key, record: $0.value.record, revision: $0.value.revision) }
    }

    var keys: some Collection<UsageEventID> {
        events.keys
    }

    var count: Int {
        events.count
    }

    subscript(id: UsageEventID) -> UsageEvent? {
        events[id].map { UsageEvent(id: id, record: $0.record, revision: $0.revision) }
    }

    /// Keeps the event unless an existing copy of its id supersedes it or it predates the window.
    mutating func insert(_ event: UsageEvent, since windowStart: Date) {
        guard event.record.timestamp >= windowStart else {
            return
        }
        if let existing = events[event.id], !event.supersedes(record: existing.record, revision: existing.revision) {
            return
        }
        events[event.id] = Stored(record: event.record, revision: event.revision)
    }

    mutating func discard(before windowStart: Date) {
        events = events.filter { $0.value.record.timestamp >= windowStart }
    }
}
