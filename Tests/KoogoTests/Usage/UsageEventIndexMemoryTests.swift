import XCTest

@testable import Koogo

final class UsageEventIndexMemoryTests: XCTestCase {
    func testRetainedHeapStoresEachEventIdentityOnce() throws {
        guard ProcessInfo.processInfo.environment["KOOGO_MEMORY_TESTS"] == "1" else {
            throw XCTSkip("Run separately with KOOGO_MEMORY_TESTS=1 to measure retained heap.")
        }
        var index = UsageEventIndex()
        let usage = UsageRecord(timestamp: usageTestTimestamp, processedTokens: 1, costUSD: 0, modelTurn: nil)
        let before = allocatedHeapBytes()

        for number in 0..<50_000 {
            index.insert(UsageEvent(id: .piAgent(entryID: String(number)), record: usage), since: .distantPast)
        }

        XCTAssertLessThan(allocatedHeapBytes() - before, 24 * 1_024 * 1_024)
        XCTAssertEqual(index.count, 50_000)
        XCTAssertEqual(index.values.reduce(0) { $0 + $1.record.processedTokens }, 50_000)
    }
}
