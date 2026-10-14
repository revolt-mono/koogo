import Foundation

struct UsageEventIndex: Sendable {
    struct Batch: ~Copyable {
        fileprivate var index: UsageEventIndex

        mutating func insert(_ event: UsageEvent) {
            index.pending.append(index.entry(event))
        }

        mutating func removeAll() {
            index = UsageEventIndex()
        }
    }

    /// Fields run from widest to narrowest, with the revision split, so the narrow ones share the identity's padding: 56 bytes a stride instead of 72.
    private struct Entry: Sendable {
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

    /// One survivor per id, ordered by id and sized exactly, so a log that stops growing holds no hash table.
    private var sealed: [Entry] = []
    private var pending: [Entry] = []
    private var models: [ModelID?] = [nil]

    var values: some Collection<UsageEvent> {
        sealed.lazy.map { [models] entry in
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
        sealed.lazy.map(\.id)
    }

    var count: Int {
        sealed.count
    }

    /// Publishes a deduplicated batch on return or throw. The batch cannot be copied or read while being built.
    mutating func update<Result>(_ body: (inout Batch) throws -> Result) rethrows -> Result {
        var batch = Batch(index: consume self)
        defer {
            batch.index.seal()
            self = batch.index
        }
        return try body(&batch)
    }

    private mutating func seal() {
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
        sealed.removeAll { $0.timestamp < windowStart }
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
