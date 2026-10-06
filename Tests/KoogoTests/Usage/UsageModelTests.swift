import XCTest

@testable import Koogo

final class UsageModelTests: UsageWorkspaceTestCase {
    @MainActor
    func testRefreshesCoalesceAndUseInjectedDate() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        var date = usageTestTimestamp
        var clockReads = 0
        let model = UsageModel(pipeline: makePipeline()) {
            clockReads += 1
            return date
        }

        XCTAssertNil(model.snapshot)
        model.refresh(providers: Provider.allCases)
        date.addTimeInterval(86_400)
        model.refresh(providers: Provider.allCases)
        XCTAssertEqual(clockReads, 1)

        try await waitUntil { model.snapshot?.providers[.codex]?.periods[.today].total.processedTokens == 0 }
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try XCTUnwrap(model.snapshot).providers[.codex]?.periods[.last30Days].total.processedTokens, 120)
    }

    @MainActor
    func testAQueuedRefreshUsesItsOwnProviderSet() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        let model = UsageModel(pipeline: makePipeline(), now: { usageTestTimestamp })

        model.refresh(providers: Provider.allCases)
        model.refresh(providers: [.claude, .piAgent, .grok])
        try await waitUntil { model.snapshot != nil && model.snapshot?.providers[.codex] == nil }

        let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(Set(snapshot.providers.keys), [.claude, .piAgent, .grok])
        XCTAssertEqual(snapshot.summary.today.current.processedTokens, 0)
    }

    @MainActor
    func testRefreshSkipsProvidersWithoutHomeUntilTheyAppear() async throws {
        let grokHome = workspace.home(of: .grok)
        try FileManager.default.removeItem(at: grokHome)
        let model = UsageModel(pipeline: makePipeline(), now: { usageTestTimestamp })

        model.refresh(providers: Provider.allCases)
        try await waitUntil { model.snapshot != nil }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), [.codex, .claude, .piAgent])

        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        model.refresh(providers: Provider.allCases)
        try await waitUntil { model.snapshot?.providers[.grok] != nil }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), Set(Provider.allCases))
    }
}
