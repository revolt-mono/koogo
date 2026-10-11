import Foundation

/// The surviving copy of every request id seen in one log, or across logs.
struct UsageEventIndex: Sendable {
    private struct Entry: Sendable {
        let id: UsageEventID
        let secondsSinceReferenceDate: TimeInterval
        let processedTokens: UInt64
        let revision: UsageEvent.Revision
        let costUSD: Decimal
        let turn: UInt32

        var timestamp: Date {
            Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
        }

        /// More output or metadata wins, then more tokens, then the earlier copy.
        func isSuperseded(by event: UsageEvent) -> Bool {
            let rank = (event.revision, event.record.processedTokens)
            let storedRank = (revision, processedTokens)
            return rank == storedRank ? event.record.timestamp < timestamp : rank > storedRank
        }
    }

    /// Ordered by id and sized exactly, so a log that stops growing holds no hash table.
    private var sealed: [Entry] = []
    private var pending: [Entry] = []
    private var pendingPositions: [UsageEventID: Int] = [:]
    /// Model turns that entries point into; the first slot stands for none.
    private var turns: [UsageRecord.ModelTurn?] = [nil]

    init() {}

    /// A sealed index of events with distinct ids that already lie inside the window.
    init(distinct events: some Sequence<UsageEvent>) {
        for event in events {
            insert(event, since: .distantPast)
        }
        seal()
    }

    var values: some Collection<UsageEvent> {
        entries.lazy.map { [turns] entry in
            UsageEvent(
                id: entry.id,
                record: UsageRecord(
                    timestamp: entry.timestamp,
                    processedTokens: entry.processedTokens,
                    costUSD: entry.costUSD,
                    modelTurn: turns[Int(entry.turn)]
                ),
                revision: entry.revision
            )
        }
    }

    var keys: some Collection<UsageEventID> {
        entries.lazy.map(\.id)
    }

    var count: Int {
        sealed.count + pending.count
    }

    private var entries: FlattenSequence<[[Entry]]> {
        [sealed, pending].joined()
    }

    /// Keeps the event unless an existing copy of its id supersedes it or it predates the window.
    mutating func insert(_ event: UsageEvent, since windowStart: Date) {
        guard event.record.timestamp >= windowStart else {
            return
        }
        if let position = pendingPositions[event.id] {
            if pending[position].isSuperseded(by: event) {
                pending[position] = entry(event)
            }
        } else if let position = sealedPosition(of: event.id) {
            if sealed[position].isSuperseded(by: event) {
                sealed[position] = entry(event)
            }
        } else {
            pendingPositions[event.id] = pending.count
            pending.append(entry(event))
        }
    }

    /// Moves pending events into the sealed ones without changing what the index holds.
    mutating func seal() {
        guard !pending.isEmpty else {
            return
        }
        sealed = (sealed + pending).sorted { $0.id < $1.id }
        pending = []
        pendingPositions = [:]
    }

    mutating func discard(before windowStart: Date) {
        seal()
        sealed.removeAll { $0.timestamp < windowStart }
    }

    private func sealedPosition(of id: UsageEventID) -> Int? {
        var range = sealed.indices
        while !range.isEmpty {
            let middle = range.lowerBound + range.count / 2
            if sealed[middle].id == id {
                return middle
            }
            range = sealed[middle].id < id ? middle + 1..<range.upperBound : range.lowerBound..<middle
        }
        return nil
    }

    private mutating func entry(_ event: UsageEvent) -> Entry {
        let record = event.record
        let turn = turns.firstIndex(of: record.modelTurn) ?? turns.endIndex
        if turn == turns.endIndex {
            turns.append(record.modelTurn)
        }
        return Entry(
            id: event.id,
            secondsSinceReferenceDate: record.timestamp.timeIntervalSinceReferenceDate,
            processedTokens: record.processedTokens,
            revision: event.revision,
            costUSD: record.costUSD,
            turn: UInt32(turn)
        )
    }
}
