import Foundation

struct UsageEventIndex: Sendable {
  struct Batch: ~Copyable {
    mutating func insert(_ event: UsageEvent) {
      pending.append(Entry(event, model: index.intern(event.record.model)))
    }

    mutating func removeAll() {
      self = Batch(index: UsageEventIndex())
    }

    fileprivate var index: UsageEventIndex
    fileprivate var pending = [Entry]()
  }

  mutating func update<Result>(_ body: (inout Batch) -> Result) -> Result {
    var batch = Batch(index: consume self)
    let result = body(&batch)
    batch.index.merge(&batch.pending)
    self = batch.index
    return result
  }

  mutating func discard(before windowStart: UsageTimestamp) {
    entries.removeAll { $0.timestamp < windowStart }
  }

  /// the narrow fields come last, keeping each entry at a 56-byte stride.
  fileprivate struct Entry: Sendable {
    init(_ event: UsageEvent, model: UInt32) {
      timestamp = event.record.timestamp
      processedTokens = event.record.processedTokens
      cost = event.record.cost
      outputTokens = event.revision.outputTokens
      id = event.id
      metadataCompleteness = event.revision.metadataCompleteness
      self.model = model
    }

    let timestamp: UsageTimestamp
    let processedTokens: UInt64
    let cost: Picodollars
    let outputTokens: UInt64
    let id: UsageEventID
    let metadataCompleteness: UInt8
    let model: UInt32

    var revision: UsageEvent.Revision {
      UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
    }

    func isSuperseded(by other: Self) -> Bool {
      let rank = (other.outputTokens, other.metadataCompleteness, other.processedTokens)
      let storedRank = (outputTokens, metadataCompleteness, processedTokens)
      return rank == storedRank
        ? other.timestamp < timestamp
        : rank > storedRank
    }
  }

  private var entries = [Entry]()
  private var models: [ModelID?] = [nil]

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

  private mutating func intern(_ model: ModelID?) -> UInt32 {
    let slot = models.firstIndex(of: model) ?? models.endIndex
    if slot == models.endIndex {
      models.append(model)
    }
    return UInt32(slot)
  }

  private func event(at position: Int) -> UsageEvent {
    let entry = entries[position]
    return UsageEvent(
      id: entry.id,
      record: UsageRecord(
        timestamp: entry.timestamp,
        processedTokens: entry.processedTokens,
        cost: entry.cost,
        model: models[Int(entry.model)],
      ),
      revision: entry.revision,
    )
  }
}

extension UsageEventIndex {
  /// an exact tie keeps the earliest index's copy.
  static func forEachUnique(in indexes: [UsageEventIndex], _ visit: (UsageEvent) -> Void) {
    for copy in Merge(indexes) {
      visit(indexes[copy.index].event(at: copy.position))
    }
  }

  private struct Merge: Sequence, IteratorProtocol {
    init(_ indexes: [UsageEventIndex]) {
      self.indexes = indexes
      heap = indexes.indices.compactMap { index in
        indexes[index].entries.first.map { Cursor(index: index, position: 0, id: $0.id) }
      }
      for slot in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
        siftDown(from: slot)
      }
    }

    struct Cursor {
      let index: Int
      var position: Int
      var id: UsageEventID

      func precedes(_ other: Self) -> Bool {
        (id, index) < (other.id, other.index)
      }
    }

    mutating func next() -> Cursor? {
      guard var kept = heap.first else {
        return nil
      }
      advance()
      while let copy = heap.first, copy.id == kept.id {
        if entry(kept).isSuperseded(by: entry(copy)) {
          kept = copy
        }
        advance()
      }
      return kept
    }

    private let indexes: [UsageEventIndex]
    private var heap: [Cursor]

    private func entry(_ cursor: Cursor) -> Entry {
      indexes[cursor.index].entries[cursor.position]
    }

    private mutating func advance() {
      let position = heap[0].position + 1
      let entries = indexes[heap[0].index].entries
      if position < entries.count {
        heap[0].position = position
        heap[0].id = entries[position].id
      } else {
        heap.swapAt(0, heap.count - 1)
        heap.removeLast()
      }
      siftDown(from: 0)
    }

    private mutating func siftDown(from start: Int) {
      var parent = start
      while case let left = 2 * parent + 1, left < heap.count {
        var smallest = heap[left].precedes(heap[parent]) ? left : parent
        if left + 1 < heap.count, heap[left + 1].precedes(heap[smallest]) {
          smallest = left + 1
        }
        guard smallest != parent else {
          return
        }
        heap.swapAt(parent, smallest)
        parent = smallest
      }
    }
  }
}
