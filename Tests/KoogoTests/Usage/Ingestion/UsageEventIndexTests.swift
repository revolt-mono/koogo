import Foundation
import Testing

@testable import Koogo

struct UsageEventIndexTests {
  @Test
  func `an update publishes only survivors and can be discarded immediately`() {
    var index = UsageEventIndex()
    let old = UsageFixture.timestamp - 1
    index.update { batch in
      batch.insert(UsageEvent.stub(.claude, id: 1, processedTokens: 10, costUSD: 0))
      batch.insert(UsageEvent.stub(.claude, id: 1, processedTokens: 20, costUSD: 0))
      batch.insert(UsageEvent.stub(.codex, id: 2, processedTokens: 30, costUSD: 0, at: old))
    }

    #expect(index.events.map(\.record.processedTokens).sorted() == [20, 30])

    index.discard(before: UsageTimestamp(UsageFixture.timestamp))

    #expect(index.events.map(\.record.processedTokens) == [20])
  }

  @Test
  func `identical copies keep the earliest timestamp`() {
    for provider in Provider.allCases {
      let id = UsageEventID(provider) { $0.combine(text: "event".utf8) }
      var index = UsageEventIndex()
      index.update { batch in
        batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: UsageFixture.timestamp + 1)))
        batch.insert(UsageEvent(id: id, record: record(tokens: 10)))
        batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: UsageFixture.timestamp + 2)))
      }

      #expect(index.events.map(\.record.timestamp.date) == [UsageFixture.timestamp], "\(provider)")
    }
  }

  @Test
  func `exact copies across indexes keep the first index copy`() {
    let cheap = UsageEvent.stub(.claude, processedTokens: 10, costUSD: 1)
    let costly = UsageEvent.stub(.claude, processedTokens: 10, costUSD: 2)

    for events in [[cheap, costly], [costly, cheap]] {
      let indexes = events.map { event in
        var index = UsageEventIndex()
        index.update { $0.insert(event) }
        return index
      }
      var visited = [UsageEvent]()
      UsageEventIndex.forEachUnique(in: indexes) { visited.append($0) }

      #expect(visited.map(\.record.cost) == [events[0].record.cost])
    }
  }

  @Test
  func `more tokens then more detail win in either insert order`() {
    let ladder = [
      claudeCopy(tokens: 30, outputTokens: 4, metadataCompleteness: 2),
      claudeCopy(tokens: 10, outputTokens: 5, metadataCompleteness: 0),
      claudeCopy(tokens: 9, outputTokens: 5, metadataCompleteness: 1),
      claudeCopy(tokens: 20, outputTokens: 5, metadataCompleteness: 1),
      claudeCopy(
        tokens: 20,
        outputTokens: 5,
        metadataCompleteness: 1,
        at: UsageFixture.timestamp.addingTimeInterval(-1),
      ),
    ]

    for (partial, complete) in zip(ladder, ladder.dropFirst()) {
      var completeFirst = UsageEventIndex()
      completeFirst.update { batch in
        batch.insert(complete)
        batch.insert(partial)
      }
      var partialFirst = UsageEventIndex()
      partialFirst.update { batch in
        batch.insert(partial)
        batch.insert(complete)
      }

      for index in [completeFirst, partialFirst] {
        #expect(index.events.count == 1)
        #expect(index.events.first?.record.processedTokens == complete.record.processedTokens)
        #expect(index.events.first?.record.timestamp == complete.record.timestamp)
      }
    }
  }

  @Test
  func `earlier updates yield only to more complete copies`() {
    var index = UsageEventIndex()
    index.update { batch in
      for id in 0..<8 {
        batch.insert(UsageEvent.stub(.claude, id: id, processedTokens: 10, costUSD: 0))
      }
    }

    index.update { batch in
      for id in 0..<8 {
        batch.insert(UsageEvent.stub(.claude, id: id, processedTokens: id.isMultiple(of: 2) ? 50 : 5, costUSD: 0))
      }
      batch.insert(UsageEvent.stub(.claude, id: 8, processedTokens: 1, costUSD: 0))
    }

    #expect(
      index.events.map(\.record.processedTokens).sorted()
        == [1] + Array(repeating: 10, count: 4) + Array(repeating: 50, count: 4)
    )
  }

  @Test
  func `restart drops both stored and pending events`() {
    var index = UsageEventIndex()
    index.update { $0.insert(UsageEvent.stub(.claude, model: "old-model", processedTokens: 10, costUSD: 0)) }
    index.update { batch in
      batch.insert(UsageEvent.stub(.claude, id: 2, model: "pending-model", processedTokens: 20, costUSD: 0))
      batch.removeAll()
      batch.insert(UsageEvent.stub(.codex, id: 3, model: "new-model", processedTokens: 30, costUSD: 0))
    }

    #expect(index.count == 1)
    #expect(index.events.first?.provider == .codex)
    #expect(index.events.first?.record.processedTokens == 30)
    #expect(index.events.first?.record.model == "new-model")
  }

  private func record(tokens: UInt64, at date: Date = UsageFixture.timestamp) -> UsageRecord {
    UsageRecord(
      timestamp: UsageTimestamp(date),
      processedTokens: tokens,
      cost: .zero,
      model: nil,
    )
  }

  private func claudeCopy(
    tokens: UInt64,
    outputTokens: UInt64,
    metadataCompleteness: UInt8,
    at date: Date = UsageFixture.timestamp,
  ) -> UsageEvent {
    UsageEvent(
      id: UsageEventID(.claude) { $0.combine(text: "message".utf8) },
      record: record(tokens: tokens, at: date),
      revision: UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness),
    )
  }
}
