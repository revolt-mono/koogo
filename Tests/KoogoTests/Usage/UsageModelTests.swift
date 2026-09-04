import XCTest

@testable import Koogo

@MainActor
final class UsageModelTests: XCTestCase {
    func testRefreshesCoalesceAndUseInjectedDate() async throws {
        let workspace = try UsageTestWorkspace()
        defer {
            try? workspace.remove()
        }
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        var date = usageTestTimestamp
        var clockReads = 0
        let model = UsageModel(
            usageService: UsageService(
                locations: workspace.locations,
                calendar: workspace.calendar
            ),
            now: {
                clockReads += 1
                return date
            }
        )

        XCTAssertNil(model.snapshot)
        model.refresh()
        model.refresh()
        XCTAssertEqual(clockReads, 1)
        var deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(try XCTUnwrap(model.snapshot).codex.today.processedTokens, 120)

        date.addTimeInterval(86_400)
        model.refresh()
        XCTAssertEqual(clockReads, 2)
        deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot?.codex.today.processedTokens == 120, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try XCTUnwrap(model.snapshot).codex.today.processedTokens, 0)
        XCTAssertEqual(try XCTUnwrap(model.snapshot).codex.month.processedTokens, 120)
    }
}
