import Foundation
import XCTest

@testable import Koogo

final class UsageEventIndexTests: XCTestCase {
    func testStableCodexAndPiIdentitiesKeepFirstOccurrence() {
        let codexID = UsageEvent.CodexID(
            threadID: "thread",
            turnID: "turn",
            ordinal: 1,
            timestamp: usageTestTimestamp,
            cumulativeTotal: 10
        )
        var index = UsageEventIndex(since: .distantPast)

        index.insert(.event(.codex(id: codexID, usage: record(tokens: 10))))
        index.insert(.event(.codex(id: codexID, usage: record(tokens: 20))))
        index.insert(.event(.piAgent(entryID: "entry", usage: record(tokens: 30))))
        index.insert(.event(.piAgent(entryID: "entry", usage: record(tokens: 40))))

        XCTAssertEqual(index.values.first { $0.provider == .codex }?.usage.processedTokens, 10)
        XCTAssertEqual(index.values.first { $0.provider == .piAgent }?.usage.processedTokens, 30)
    }

    func testClaudeIdentityKeepsPreferredRevisionAcrossInsertAndMerge() {
        let id = UsageEvent.ClaudeID(messageID: "message", requestID: "request")
        let revisions = [
            UsageEvent.ClaudeRevision(usage: record(tokens: 30), outputTokens: 4, metadataCompleteness: 2),
            UsageEvent.ClaudeRevision(usage: record(tokens: 10), outputTokens: 5, metadataCompleteness: 0),
            UsageEvent.ClaudeRevision(usage: record(tokens: 9), outputTokens: 5, metadataCompleteness: 1),
            UsageEvent.ClaudeRevision(usage: record(tokens: 20), outputTokens: 5, metadataCompleteness: 1),
            UsageEvent.ClaudeRevision(
                usage: record(tokens: 20, at: usageTestTimestamp.addingTimeInterval(1)),
                outputTokens: 5,
                metadataCompleteness: 1
            ),
        ]

        for (partial, complete) in zip(revisions, revisions.dropFirst()) {
            var inserted = UsageEventIndex(since: .distantPast)
            inserted.insert(.event(.claude(id: id, revision: complete)))
            inserted.insert(.event(.claude(id: id, revision: partial)))
            var merged = UsageEventIndex(since: .distantPast)
            merged.insert(.event(.claude(id: id, revision: partial)))
            inserted.merge(merged)
            merged.merge(inserted)

            for index in [inserted, merged] {
                XCTAssertEqual(index.values.count, 1)
                XCTAssertEqual(index.values.first?.usage.processedTokens, complete.usage.processedTokens)
                XCTAssertEqual(index.values.first?.usage.timestamp, complete.usage.timestamp)
            }
        }
    }

    func testDiscardRemovesEveryProviderBeforeHistoryStart() {
        let historyStart = usageTestTimestamp
        let old = historyStart.addingTimeInterval(-1)
        var index = UsageEventIndex(since: .distantPast)
        index.insert(.event(usageEvent(.codex, id: 1, processedTokens: 1, costUSD: 0, at: old)))
        index.insert(.event(usageEvent(.claude, id: 2, processedTokens: 2, costUSD: 0, at: old)))
        index.insert(.event(usageEvent(.piAgent, id: 3, processedTokens: 3, costUSD: 0, at: old)))
        index.insert(.event(usageEvent(.codex, id: 4, processedTokens: 4, costUSD: 0)))

        index.discard(before: historyStart)

        XCTAssertEqual(index.values.map(\.usage.processedTokens), [4])
    }

    private func record(tokens: UInt64, at date: Date = usageTestTimestamp) -> UsageRecord {
        UsageRecord(
            timestamp: date,
            processedTokens: tokens,
            costUSD: 0,
            modelTurn: nil
        )
    }
}
