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
        var index = UsageEventIndex()

        index.insert(.codex(id: codexID, usage: record(tokens: 10)))
        index.insert(.codex(id: codexID, usage: record(tokens: 20)))
        index.insert(.piAgent(entryID: "entry", usage: record(tokens: 30)))
        index.insert(.piAgent(entryID: "entry", usage: record(tokens: 40)))

        XCTAssertEqual(index.values.first { $0.provider == .codex }?.usage.processedTokens, 10)
        XCTAssertEqual(index.values.first { $0.provider == .piAgent }?.usage.processedTokens, 30)
    }

    func testClaudeIdentityKeepsPreferredRevisionAcrossInsertAndMerge() {
        let id = UsageEvent.ClaudeID(messageID: "message", requestID: "request")
        let partial = UsageEvent.claude(
            id: id,
            usage: record(tokens: 10),
            revision: revision(output: 5, metadata: 0, tokens: 10)
        )
        let complete = UsageEvent.claude(
            id: id,
            usage: record(tokens: 20),
            revision: revision(output: 5, metadata: 1, tokens: 20)
        )
        var inserted = UsageEventIndex()
        inserted.insert(complete)
        inserted.insert(partial)
        var merged = UsageEventIndex()
        merged.insert(partial)
        merged.merge(inserted)

        XCTAssertEqual(inserted.values.first?.usage.processedTokens, 20)
        XCTAssertEqual(merged.values.first?.usage.processedTokens, 20)
    }

    func testDiscardRemovesEveryProviderBeforeHistoryStart() {
        let historyStart = usageTestTimestamp
        let old = historyStart.addingTimeInterval(-1)
        var index = UsageEventIndex()
        index.insert(usageEvent(.codex, id: 1, processedTokens: 1, costUSD: 0, at: old))
        index.insert(usageEvent(.claude, id: 2, processedTokens: 2, costUSD: 0, at: old))
        index.insert(usageEvent(.piAgent, id: 3, processedTokens: 3, costUSD: 0, at: old))
        index.insert(usageEvent(.codex, id: 4, processedTokens: 4, costUSD: 0))

        index.discard(before: historyStart)

        XCTAssertEqual(index.values.map(\.usage.processedTokens), [4])
    }

    private func record(tokens: UInt64) -> UsageRecord {
        UsageRecord(
            timestamp: usageTestTimestamp,
            processedTokens: tokens,
            costUSD: 0,
            modelTurn: nil
        )
    }

    private func revision(
        output: UInt64,
        metadata: Int,
        tokens: UInt64
    ) -> UsageEvent.ClaudeRevision {
        UsageEvent.ClaudeRevision(
            outputTokens: output,
            metadataCompleteness: metadata,
            processedTokens: tokens,
            timestamp: usageTestTimestamp
        )
    }
}
