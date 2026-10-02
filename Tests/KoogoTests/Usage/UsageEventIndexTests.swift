import Foundation
import XCTest

@testable import Koogo

final class UsageEventIndexTests: XCTestCase {
    func testIdenticalCopiesKeepTheOneLoggedFirst() {
        let ids: [UsageEventID] = [
            .codex(turnID: "turn", cumulativeTotal: 10),
            .piAgent(entryID: "entry"),
            .grok(eventID: "event", timestampMilliseconds: grokMilliseconds(usageTestTimestamp)),
        ]

        for id in ids {
            var index = UsageEventIndex()
            index.insert(
                UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 1)),
                since: .distantPast
            )
            index.insert(UsageEvent(id: id, record: record(tokens: 10)), since: .distantPast)
            index.insert(
                UsageEvent(id: id, record: record(tokens: 10, at: usageTestTimestamp + 2)),
                since: .distantPast
            )

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
            completeFirst.insert(complete, since: .distantPast)
            completeFirst.insert(partial, since: .distantPast)
            var partialFirst = UsageEventIndex()
            partialFirst.insert(partial, since: .distantPast)
            partialFirst.insert(complete, since: .distantPast)

            for index in [completeFirst, partialFirst] {
                XCTAssertEqual(index.values.count, 1)
                XCTAssertEqual(index.values.first?.record.processedTokens, complete.record.processedTokens)
                XCTAssertEqual(index.values.first?.record.timestamp, complete.record.timestamp)
            }
        }
    }

    func testInsertSkipsEventsBeforeTheWindowAndDiscardDropsThem() {
        let windowStart = usageTestTimestamp
        let old = windowStart.addingTimeInterval(-1)
        var index = UsageEventIndex()
        index.insert(usageEvent(.codex, id: 1, processedTokens: 1, costUSD: 0, at: old), since: windowStart)
        for (id, provider) in Provider.allCases.enumerated() {
            index.insert(usageEvent(provider, id: id, processedTokens: 2, costUSD: 0, at: old), since: .distantPast)
        }
        index.insert(usageEvent(.codex, id: 100, processedTokens: 4, costUSD: 0), since: windowStart)
        XCTAssertEqual(index.count, 5)

        index.discard(before: windowStart)

        XCTAssertEqual(index.values.map(\.record.processedTokens), [4])
    }

    func testTallyKeepsTheLatestUnpricedTimestampInsideTheWindow() {
        let windowStart = usageTestTimestamp
        var tally = LogTally()
        tally.noteUnpricedModel("old", at: windowStart - 1, since: windowStart)
        tally.noteUnpricedModel("kept", at: windowStart + 1, since: windowStart)
        tally.noteUnpricedModel("kept", at: windowStart, since: windowStart)
        tally.noteUnpricedModel("aging", at: windowStart, since: windowStart)
        tally.countMalformedLines(1)

        tally.discard(before: windowStart + 1)

        XCTAssertEqual(Array(tally.unpricedModelIDs), ["kept"])
        XCTAssertEqual(tally.malformedLines, 1)
    }

    private func record(tokens: UInt64, at date: Date = usageTestTimestamp) -> UsageRecord {
        UsageRecord(
            timestamp: date,
            processedTokens: tokens,
            costUSD: 0,
            modelTurn: nil
        )
    }

    private func claudeCopy(
        tokens: UInt64,
        outputTokens: UInt64,
        metadataCompleteness: Int,
        at date: Date = usageTestTimestamp
    ) -> UsageEvent {
        UsageEvent(
            id: .claude(messageID: "message", requestID: "request"),
            record: record(tokens: tokens, at: date),
            revision: UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
        )
    }
}
