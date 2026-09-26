import Foundation
import XCTest

@testable import Koogo

final class UsageEventIndexTests: XCTestCase {
    func testEarlierCopyWinsForKeysWithoutRevisions() {
        let keys: [UsageEvent.Key] = [
            .codex(turnID: "turn", cumulativeTotal: 10),
            .piAgent(entryID: "entry"),
            .grok(eventID: "event", timestamp: usageTestTimestamp),
        ]

        for key in keys {
            var index = UsageEventIndex(since: .distantPast)
            index.insert(.event(UsageEvent(key: key, usage: record(tokens: 10, at: usageTestTimestamp + 1))))
            index.insert(.event(UsageEvent(key: key, usage: record(tokens: 20))))
            index.insert(.event(UsageEvent(key: key, usage: record(tokens: 30))))
            var later = UsageEventIndex(since: .distantPast)
            later.insert(.event(UsageEvent(key: key, usage: record(tokens: 40))))
            index.merge(later)

            XCTAssertEqual(index.values.map(\.usage.processedTokens), [20], "\(key)")
        }
    }

    func testClaudeKeyKeepsTheHighestRevisionAcrossInsertAndMerge() {
        let ladder = [
            claudeCopy(tokens: 30, outputTokens: 4, metadataCompleteness: 2),
            claudeCopy(tokens: 10, outputTokens: 5, metadataCompleteness: 0),
            claudeCopy(tokens: 9, outputTokens: 5, metadataCompleteness: 1),
            claudeCopy(tokens: 20, outputTokens: 5, metadataCompleteness: 1),
            claudeCopy(
                tokens: 20,
                outputTokens: 5,
                metadataCompleteness: 1,
                at: usageTestTimestamp.addingTimeInterval(1)
            ),
        ]

        for (partial, complete) in zip(ladder, ladder.dropFirst()) {
            var inserted = UsageEventIndex(since: .distantPast)
            inserted.insert(.event(complete))
            inserted.insert(.event(partial))
            var merged = UsageEventIndex(since: .distantPast)
            merged.insert(.event(partial))
            inserted.merge(merged)
            merged.merge(inserted)

            for index in [inserted, merged] {
                XCTAssertEqual(index.values.count, 1)
                XCTAssertEqual(index.values.first?.usage.processedTokens, complete.usage.processedTokens)
                XCTAssertEqual(index.values.first?.usage.timestamp, complete.usage.timestamp)
            }
        }
    }

    func testDiscardRemovesEventsAndUnpricedModelsBeforeHistoryStart() {
        let historyStart = usageTestTimestamp
        let old = historyStart.addingTimeInterval(-1)
        var index = UsageEventIndex(since: .distantPast)
        for (id, provider) in UsageProvider.allCases.enumerated() {
            index.insert(.event(usageEvent(provider, id: id, processedTokens: 1, costUSD: 0, at: old)))
        }
        index.insert(.unpricedModel(id: "old-model", timestamp: old))
        index.insert(.event(usageEvent(.codex, id: 100, processedTokens: 4, costUSD: 0)))

        index.discard(before: historyStart)

        XCTAssertEqual(index.values.map(\.usage.processedTokens), [4])
        XCTAssertEqual(index.unpricedModelIDs, [])
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
            key: .claude(messageID: "message", requestID: "request"),
            usage: record(tokens: tokens, at: date),
            revision: UsageEvent.Revision(outputTokens: outputTokens, metadataCompleteness: metadataCompleteness)
        )
    }
}
