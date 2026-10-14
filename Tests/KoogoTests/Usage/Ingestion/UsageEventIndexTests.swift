import Foundation
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

        XCTAssertEqual(index.count, 2)
        XCTAssertEqual(Set(index.keys).count, 2)
        XCTAssertEqual(index.values.map(\.record.processedTokens).sorted(), [20, 30])

        index.discard(before: usageTestTimestamp)

        XCTAssertEqual(index.values.map(\.record.processedTokens), [20])
    }

    func testIdenticalCopiesKeepTheOneLoggedFirst() {
        let ids: [UsageEventID] = [
            .codex(turnID: "turn", cumulativeTotal: 10),
            .piAgent(entryID: "entry"),
            .grok(eventID: "event", timestampMilliseconds: grokMilliseconds(usageTestTimestamp)),
        ]

        for id in ids {
            var index = UsageEventIndex()
            index.update { batch in
                batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 1)))
                batch.insert(UsageEvent(id: id, record: record(tokens: 10)))
                batch.insert(UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 2)))
            }

            XCTAssertEqual(index.values.map(\.record.timestamp), [usageTestTimestamp], "\(id)")
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
                XCTAssertEqual(index.values.count, 1)
                XCTAssertEqual(index.values.first?.record.processedTokens, complete.record.processedTokens)
                XCTAssertEqual(index.values.first?.record.timestamp, complete.record.timestamp)
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
            index.values.map(\.record.processedTokens).sorted(),
            [1] + Array(repeating: 10, count: 4) + Array(repeating: 50, count: 4)
        )
    }

    func testDiscardDropsEventsBeforeTheWindow() {
        let windowStart = usageTestTimestamp
        let old = windowStart.addingTimeInterval(-1)
        var index = UsageEventIndex()
        index.update { batch in
            for (id, provider) in Provider.allCases.enumerated() {
                batch.insert(usageEvent(provider, id: id, processedTokens: 2, costUSD: 0, at: old))
            }
            batch.insert(usageEvent(.codex, id: 100, processedTokens: 4, costUSD: 0))
        }
        XCTAssertEqual(index.count, 5)

        index.discard(before: windowStart)

        XCTAssertEqual(index.values.map(\.record.processedTokens), [4])
    }

    func testThrowingAnUpdatePublishesTheCompletedPrefixAndAllowsAnotherUpdate() {
        struct Interrupted: Error {}
        var index = UsageEventIndex()
        XCTAssertThrowsError(
            try index.update { batch in
                batch.insert(usageEvent(.claude, id: 1, processedTokens: 10, costUSD: 0))
                batch.insert(usageEvent(.claude, id: 1, processedTokens: 20, costUSD: 0))
                throw Interrupted()
            }
        )
        XCTAssertEqual(index.values.map(\.record.processedTokens), [20])

        index.update { $0.insert(usageEvent(.claude, id: 2, processedTokens: 30, costUSD: 0)) }

        XCTAssertEqual(index.values.map(\.record.processedTokens).sorted(), [20, 30])
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
        XCTAssertEqual(index.values.first?.provider, .codex)
        XCTAssertEqual(index.values.first?.record.processedTokens, 30)
        XCTAssertEqual(index.values.first?.record.model, "new-model")
    }

    func testEarlierReadersKeepTheirEventsAndModelNamesAcrossUpdates() {
        var index = UsageEventIndex()
        index.update { $0.insert(usageEvent(.claude, id: 1, model: "old-model", processedTokens: 10, costUSD: 0)) }
        let earlier = index.values
        let copy = index

        index.update { batch in
            batch.insert(usageEvent(.claude, id: 1, model: "revised-model", processedTokens: 30, costUSD: 0))
            batch.insert(usageEvent(.codex, id: 2, model: "new-model", processedTokens: 20, costUSD: 0))
        }

        XCTAssertEqual(earlier.first?.provider, .claude)
        XCTAssertEqual(earlier.first?.record.model, "old-model")
        XCTAssertEqual(copy.values.first?.record.model, "old-model")
        XCTAssertEqual(copy.values.map(\.record.processedTokens), [10])
        XCTAssertEqual(index.values.map(\.record.processedTokens).sorted(), [20, 30])
    }

    func testBatchReadersAndEscapingWritersAreRejectedByTheCompiler() async throws {
        let allowed = try await compileKoogoClient(
            """
            func verify(_ event: UsageEvent) {
                var index = UsageEventIndex()
                index.update { $0.insert(event) }
                _ = index.values
            }
            """
        )
        XCTAssertEqual(allowed.status, 0, allowed.diagnostics)

        let reader = try await compileKoogoClient(
            """
            func verify() {
                var index = UsageEventIndex()
                index.update { batch in _ = batch.values }
            }
            """
        )
        XCTAssertNotEqual(reader.status, 0)
        XCTAssertTrue(reader.diagnostics.contains("has no member 'values'"), reader.diagnostics)

        for (transfer, expected) in [("batch", "is consuming"), ("consume batch", "missing reinitialization")] {
            let escaped = try await compileKoogoClient(
                """
                func verify() {
                    var retained: UsageEventIndex.Batch?
                    var index = UsageEventIndex()
                    index.update { batch in retained = \(transfer) }
                }
                """
            )
            XCTAssertNotEqual(escaped.status, 0)
            XCTAssertTrue(escaped.diagnostics.contains(expected), escaped.diagnostics)
        }
    }

    func testTallyKeepsTheLatestUnpricedTimestampInsideTheWindow() {
        let windowStart = usageTestTimestamp
        var tally = LogTally()
        tally.noteUnpricedModel("old", at: windowStart - 1)
        tally.noteUnpricedModel("kept", at: windowStart + 1)
        tally.noteUnpricedModel("kept", at: windowStart)
        tally.noteUnpricedModel("aging", at: windowStart)
        tally.noteMalformedLine()

        tally.discard(before: windowStart + 1)

        XCTAssertEqual(Array(tally.unpricedModelIDs), ["kept"])
        XCTAssertEqual(tally.malformedLines, 1)
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
            id: .claude(messageID: "message", requestID: "request"),
            record: record(tokens: tokens, at: date),
            revision: UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
        )
    }
}
