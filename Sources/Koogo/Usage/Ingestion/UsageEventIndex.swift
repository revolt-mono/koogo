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

    /// field order reuses identity padding, keeping each entry at a 56-byte stride.
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

    private var deduplicatedEntries: [Entry] = []
    private var pending: [Entry] = []
    private var models: [ModelID?] = [nil]

    var values: some Collection<UsageEvent> {
        deduplicatedEntries.lazy.map { [models] entry in
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
        deduplicatedEntries.lazy.map(\.id)
    }

    var count: Int {
        deduplicatedEntries.count
    }

    /// publishes a deduplicated batch on return; the batch cannot be copied or read during construction.
    mutating func update<Result>(_ body: (inout Batch) -> Result) -> Result {
        var batch = Batch(index: consume self)
        let result = body(&batch)
        batch.index.deduplicate()
        self = batch.index
        return result
    }

    private mutating func deduplicate() {
        guard !pending.isEmpty else {
            return
        }
        deduplicatedEntries += pending
        pending = []
        deduplicatedEntries.sort { $0.id < $1.id }
        var survivorCount = 0
        for position in deduplicatedEntries.indices {
            if survivorCount > 0, deduplicatedEntries[survivorCount - 1].id == deduplicatedEntries[position].id {
                if deduplicatedEntries[survivorCount - 1].isSuperseded(by: deduplicatedEntries[position]) {
                    deduplicatedEntries[survivorCount - 1] = deduplicatedEntries[position]
                }
            } else {
                deduplicatedEntries[survivorCount] = deduplicatedEntries[position]
                survivorCount += 1
            }
        }
        deduplicatedEntries = deduplicatedEntries.withUnsafeBufferPointer { Array($0.prefix(survivorCount)) }
    }

    mutating func discard(before windowStart: Date) {
        deduplicatedEntries.removeAll { $0.timestamp < windowStart }
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
