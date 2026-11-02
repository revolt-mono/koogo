import XCTest

@testable import Koogo

final class UsageEventIndexTests: XCTestCase {
    func testAnUpdatePublishesOnlySurvivorsAndCanBeDiscardedImmediately() {
        var index = UsageEventIndex()
        let old = usageTestTimestamp - 1
        index.update { batch in
            batch.insert(usageEvent(.claude, id: 1, processedTokens: 10, costUSD: 0))
            batch.insert(usageEvent(.claude, id: 1, processedTokens: 20, costUSD: 0))
            batch.insert(usageEvent(.codex, id: 2, processedTokens: 30, costUSD: 0, at: old))
        }

        XCTAssertEqual(index.events.map(\.record.processedTokens).sorted(), [20, 30])

        index.discard(before: usageTestTimestamp)

        XCTAssertEqual(index.events.map(\.record.processedTokens), [20])
    }

    func testIdenticalCopiesKeepTheEarliestTimestamp() {
        let ids: [UsageEventID] = [
            .codex(responseID: "response".utf8),
            .piAgent(entryID: "entry".utf8, timestamp: usageTestTimestamp),
            .grok(eventID: "event".utf8, timestampMilliseconds: grokMilliseconds(usageTestTimestamp)),
        ]

        for id in ids {
            var index = UsageEventIndex()
            index.update { batch in
                batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 1)))
                batch.insert(UsageEvent(id: id, record: record(tokens: 10)))
                batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 2)))
            }

            XCTAssertEqual(index.events.map(\.record.timestamp), [usageTestTimestamp], "\(id)")
        }
    }

    func testExactCopiesAcrossIndexesKeepTheFirstIndexCopy() {
        let cheap = usageEvent(.claude, processedTokens: 10, costUSD: 1)
        let costly = usageEvent(.claude, processedTokens: 10, costUSD: 2)

        for events in [[cheap, costly], [costly, cheap]] {
            let indexes = events.map { event in
                var index = UsageEventIndex()
                index.update { $0.insert(event) }
                return index
            }
            var visited: [UsageEvent] = []
            UsageEventIndex.forEachUnique(in: indexes) { visited.append($0) }

            XCTAssertEqual(visited.map(\.record.cost), [events[0].record.cost])
        }
    }

    func testMoreTokensThenMoreDetailWinInEitherInsertOrder() {
        let ladder = [
            claudeCopy(tokens: 30, outputTokens: 4, metadataCompleteness: 2),
            claudeCopy(tokens: 10, outputTokens: 5, metadataCompleteness: 0),
            claudeCopy(tokens: 9, outputTokens: 5, metadataCompleteness: 1),
            claudeCopy(tokens: 20, outputTokens: 5, metadataCompleteness: 1),
            claudeCopy(
                tokens: 20,
                outputTokens: 5,
                metadataCompleteness: 1,
                at: usageTestTimestamp.addingTimeInterval(-1)
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
                XCTAssertEqual(index.events.count, 1)
                XCTAssertEqual(index.events.first?.record.processedTokens, complete.record.processedTokens)
                XCTAssertEqual(index.events.first?.record.timestamp, complete.record.timestamp)
            }
        }
    }

    func testEarlierUpdatesYieldOnlyToMoreCompleteCopies() {
        var index = UsageEventIndex()
        index.update { batch in
            for id in 0..<8 {
                batch.insert(usageEvent(.claude, id: id, processedTokens: 10, costUSD: 0))
            }
        }

        index.update { batch in
            for id in 0..<8 {
                batch.insert(usageEvent(.claude, id: id, processedTokens: id.isMultiple(of: 2) ? 50 : 5, costUSD: 0))
            }
            batch.insert(usageEvent(.claude, id: 8, processedTokens: 1, costUSD: 0))
        }

        XCTAssertEqual(
            index.events.map(\.record.processedTokens).sorted(),
            [1] + Array(repeating: 10, count: 4) + Array(repeating: 50, count: 4)
        )
    }

    func testRestartDropsBothStoredAndPendingEventsAndTheirModels() {
        var index = UsageEventIndex()
        index.update { $0.insert(usageEvent(.claude, model: "old-model", processedTokens: 10, costUSD: 0)) }
        index.update { batch in
            batch.insert(usageEvent(.claude, id: 2, model: "pending-model", processedTokens: 20, costUSD: 0))
            batch.removeAll()
            batch.insert(usageEvent(.codex, id: 3, model: "new-model", processedTokens: 30, costUSD: 0))
        }

        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.events.first?.provider, .codex)
        XCTAssertEqual(index.events.first?.record.processedTokens, 30)
        XCTAssertEqual(index.events.first?.record.model, "new-model")
    }

    private func record(tokens: UInt64, at date: Date = usageTestTimestamp) -> UsageRecord {
        UsageRecord(
            timestamp: date,
            processedTokens: tokens,
            cost: .zero,
            model: nil
        )
    }

    private func claudeCopy(
        tokens: UInt64,
        outputTokens: UInt64,
        metadataCompleteness: UInt8,
        at date: Date = usageTestTimestamp
    ) -> UsageEvent {
        UsageEvent(
            id: .claude(messageID: "message".utf8, requestID: "request".utf8),
            record: record(tokens: tokens, at: date),
            revision: UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
        )
    }
}
