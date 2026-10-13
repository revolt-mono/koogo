import Foundation

struct UsageEventIndex: Sendable {
    private struct Entry: Sendable {
        let id: UsageEventID
        let secondsSinceReferenceDate: TimeInterval
        let processedTokens: UInt64
        let revision: UsageEvent.Revision
        let costUSD: Decimal
        let model: UInt32

        var timestamp: Date {
            Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
        }

        func isSuperseded(by other: Self) -> Bool {
            let rank = (other.revision, other.processedTokens)
            let storedRank = (revision, processedTokens)
            return rank == storedRank ? other.timestamp < timestamp : rank > storedRank
        }
    }

    /// One survivor per id, ordered by id and sized exactly, so a log that stops growing holds no hash table.
    private var sealed: [Entry] = []
    private var pending: [Entry] = []
    private var models: [ModelID?] = [nil]

    init() {}

    var values: some Collection<UsageEvent> {
        entries.lazy.map { [models] entry in
            UsageEvent(
                id: entry.id,
                record: UsageRecord(
                    timestamp: entry.timestamp,
                    processedTokens: entry.processedTokens,
                    costUSD: entry.costUSD,
                    model: models[Int(entry.model)]
                ),
                revision: entry.revision
            )
        }
    }

    var keys: some Collection<UsageEventID> {
        entries.lazy.map(\.id)
    }

    var count: Int {
        entries.count
    }

    private var entries: [Entry] {
        precondition(pending.isEmpty, "seal the index before reading it")
        return sealed
    }

    mutating func insert(_ event: UsageEvent, since windowStart: Date) {
        guard event.record.timestamp >= windowStart else {
            return
        }
        pending.append(entry(event))
    }

    /// Keeps the surviving copy of each id among the sealed and pending events, which readers require.
    mutating func seal() {
        guard !pending.isEmpty else {
            return
        }
        sealed += pending
        pending = []
        sealed.sort { $0.id < $1.id }
        var survivorCount = 0
        for position in sealed.indices {
            if survivorCount > 0, sealed[survivorCount - 1].id == sealed[position].id {
                if sealed[survivorCount - 1].isSuperseded(by: sealed[position]) {
                    sealed[survivorCount - 1] = sealed[position]
                }
            } else {
                sealed[survivorCount] = sealed[position]
                survivorCount += 1
            }
        }
        sealed = sealed.withUnsafeBufferPointer { Array($0.prefix(survivorCount)) }
    }

    mutating func discard(before windowStart: Date) {
        seal()
        sealed.removeAll { $0.timestamp < windowStart }
    }

    private mutating func entry(_ event: UsageEvent) -> Entry {
        let record = event.record
        let model = models.firstIndex(of: record.model) ?? models.endIndex
        if model == models.endIndex {
            models.append(record.model)
        }
        return Entry(
            id: event.id,
            secondsSinceReferenceDate: record.timestamp.timeIntervalSinceReferenceDate,
            processedTokens: record.processedTokens,
            revision: event.revision,
            costUSD: record.costUSD,
            model: UInt32(model)
        )
    }
}
