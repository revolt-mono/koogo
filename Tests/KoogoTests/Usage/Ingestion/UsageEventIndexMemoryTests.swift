import Testing

@testable import Koogo

extension MemoryMeasurement {
  struct UsageEventIndexMemoryTests {
    @Test
    func `retained heap stores each event identity once`() {
      var index = UsageEventIndex()
      let usage = UsageRecord(timestamp: UsageTimestamp(UsageFixture.timestamp), processedTokens: 1, cost: .zero, model: nil)
      let before = MemoryMeasurement.allocatedHeapBytes()

      index.update { batch in
        for number in 0..<50_000 {
          batch.insert(UsageEvent(id: UsageEventID(.piAgent) { $0.combine(number) }, record: usage))
        }
      }

      // one 56-byte entry per event retains about 4 MiB; a second copy of each identity exceeds the bound.
      #expect(MemoryMeasurement.allocatedHeapBytes() - before < 6 * 1_024 * 1_024)
      #expect(index.events.reduce(0) { $0 + $1.record.processedTokens } == 50_000)
    }
  }
}
