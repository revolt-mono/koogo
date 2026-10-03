import XCTest

@testable import Koogo

final class LogStoreMemoryTests: UsageWorkspaceTestCase {
    func testVisitingEventsDoesNotCopyTheStore() throws {
        guard ProcessInfo.processInfo.environment["KOOGO_MEMORY_TESTS"] == "1" else {
            throw XCTSkip("Run separately with KOOGO_MEMORY_TESTS=1 to measure retained heap.")
        }
        let last = codexUsage(input: 100, output: 20)
        let turns = (1...20_000).map { turn in
            let total = codexUsage(input: 100 * turn, output: 20 * turn)
            return codexTurn(id: "turn-\(turn)") + "\n" + codexTokenCount(last: last, total: total) + "\n"
        }
        try workspace.write(turns.joined(), to: workspace.codexSessions.appending(path: "session.jsonl"))
        var store = LogStore()
        _ = store.sync(
            roots: Provider.codex.usageLogRoots(home: workspace.root),
            since: now.addingTimeInterval(-86_400)
        )

        let before = allocatedHeapBytes()
        var peak = before
        var visited = 0
        let stats = store.collect { _ in
            visited += 1
            if visited.isMultiple(of: 1_000) {
                peak = max(peak, allocatedHeapBytes())
            }
        }

        XCTAssertEqual(visited, 20_000)
        XCTAssertEqual(stats.events[.codex], 20_000)
        XCTAssertLessThan(peak - before, 2 * 1_024 * 1_024)
    }
}
