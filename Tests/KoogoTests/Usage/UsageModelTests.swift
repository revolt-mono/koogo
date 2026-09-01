import XCTest

@testable import Koogo

@MainActor
final class UsageModelTests: XCTestCase {
    func testRefreshUsesInjectedDate() async throws {
        let workspace = try UsageTestWorkspace()
        defer {
            try? workspace.remove()
        }
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let model = UsageModel(
            usageService: UsageService(
                locations: workspace.locations,
                calendar: workspace.calendar
            ),
            now: { usageTestTimestamp }
        )

        XCTAssertNil(model.snapshot)
        model.refresh()
        let deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(try XCTUnwrap(model.snapshot).codex.month.processedTokens, 120)
    }
}
