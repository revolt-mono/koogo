import Foundation

struct UsageEventIndex: Sendable {
    struct Batch: ~Copyable {
        fileprivate var index: UsageEventIndex
        fileprivate var pending: [Entry] = []

        mutating func insert(_ event: UsageEvent) {
            pending.append(index.entry(event))
        }

        mutating func removeAll() {
            self = Batch(index: UsageEventIndex())
        }
    }

    /// field order reuses identity padding, keeping each entry at a 56-byte stride.
    fileprivate struct Entry: Sendable {
        let secondsSinceReferenceDate: TimeInterval
        let processedTokens: UInt64
        let cost: Picodollars
        let outputTokens: UInt64
        let id: UsageEventID
        let metadataCompleteness: UInt8
        let model: UInt32

        var timestamp: Date {
            Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
        }

        var revision: UsageEvent.Revision {
            UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
        }

        func isSuperseded(by other: Self) -> Bool {
            let rank = (other.revision, other.processedTokens)
            let storedRank = (revision, processedTokens)
            return rank == storedRank ? other.timestamp < timestamp : rank > storedRank
        }
    }

    private var entries: [Entry] = []
    private var models: [ModelID?] = [nil]

    var values: some Collection<UsageEvent> {
        entries.lazy.map { [models] entry in
            UsageEvent(
                id: entry.id,
                record: UsageRecord(
                    timestamp: entry.timestamp,
                    processedTokens: entry.processedTokens,
                    cost: entry.cost,
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

    /// publishes the batch, deduplicated, when the body returns.
    mutating func update<Result>(_ body: (inout Batch) -> Result) -> Result {
        var batch = Batch(index: consume self)
        let result = body(&batch)
        batch.index.merge(&batch.pending)
        self = batch.index
        return result
    }

    /// empties `pending` before sorting so the batch is not held alongside the compacted copy.
    private mutating func merge(_ pending: inout [Entry]) {
        guard !pending.isEmpty else {
            return
        }
        entries += pending
        pending = []
        entries.sort { $0.id < $1.id }
        var survivorCount = 0
        for position in entries.indices {
            if survivorCount > 0, entries[survivorCount - 1].id == entries[position].id {
                if entries[survivorCount - 1].isSuperseded(by: entries[position]) {
                    entries[survivorCount - 1] = entries[position]
                }
            } else {
                entries[survivorCount] = entries[position]
                survivorCount += 1
            }
        }
        entries = entries.withUnsafeBufferPointer { Array($0.prefix(survivorCount)) }
    }

    mutating func discard(before windowStart: Date) {
        entries.removeAll { $0.timestamp < windowStart }
    }

    private mutating func entry(_ event: UsageEvent) -> Entry {
        let record = event.record
        let model = models.firstIndex(of: record.model) ?? models.endIndex
        if model == models.endIndex {
            models.append(record.model)
        }
        return Entry(
            secondsSinceReferenceDate: record.timestamp.timeIntervalSinceReferenceDate,
            processedTokens: record.processedTokens,
            cost: record.cost,
            outputTokens: event.revision.outputTokens,
            id: event.id,
            metadataCompleteness: event.revision.metadataCompleteness,
            model: UInt32(model)
        )
    }
}
