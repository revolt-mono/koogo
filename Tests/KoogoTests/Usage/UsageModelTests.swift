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
        let model = UsageModel(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            defaults: try makeIsolatedDefaults(),
            now: {
                clockReads += 1
                return date
            }
        )

        XCTAssertNil(model.snapshot)
        model.refresh()
        date.addTimeInterval(86_400)
        model.refresh()
        XCTAssertEqual(clockReads, 1)

        try await waitUntil { model.snapshot?.providers[.codex]?.today.processedTokens == 0 }
        XCTAssertEqual(clockReads, 2)
        XCTAssertEqual(try XCTUnwrap(model.snapshot).providers[.codex]?.month.processedTokens, 120)
    }

    @MainActor
    func testDisabledProviderPersistsAndLeavesSnapshotEvenMidRefresh() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        let defaults = try makeIsolatedDefaults()
        let model = UsageModel(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            defaults: defaults,
            now: { usageTestTimestamp }
        )

        model.refresh()
        model.setEnabled(false, for: .codex)
        try await waitUntil { model.snapshot != nil && model.snapshot?.providers[.codex] == nil }

        let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(Set(snapshot.providers.keys), [.claude, .piAgent, .grok])
        XCTAssertEqual(snapshot.summary.today.current.processedTokens, 0)
        XCTAssertEqual(
            UsageModel(usageService: UsageService(), defaults: defaults).enabledProviders,
            [.claude, .piAgent, .grok]
        )
    }

    @MainActor
    func testRefreshSkipsProvidersWithoutHomeUntilTheyAppear() async throws {
        let grokHome = locations.home(of: .grok)
        try FileManager.default.removeItem(at: grokHome)
        let model = UsageModel(
            usageService: UsageService(locations: locations, calendar: usageTestCalendar),
            defaults: try makeIsolatedDefaults(),
            now: { usageTestTimestamp }
        )

        XCTAssertEqual(model.refresh(), [.codex, .claude, .piAgent])
        try await waitUntil { model.snapshot != nil }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), [.codex, .claude, .piAgent])

        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        XCTAssertEqual(model.refresh(), Set(Provider.allCases))
        try await waitUntil { model.snapshot?.providers[.grok] != nil }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), Set(Provider.allCases))
    }

    @MainActor
    func testMovedProviderTakesTheTargetSlotAndPersists() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(["grok", "codex", "grok"], forKey: "usage-provider-order")
        let model = UsageModel(usageService: UsageService(), defaults: defaults, now: { usageTestTimestamp })
        XCTAssertEqual(model.providerOrder, [.grok, .codex, .claude, .piAgent])

        model.moveProvider(.piAgent, to: .codex)
        XCTAssertEqual(model.providerOrder, [.grok, .piAgent, .codex, .claude])
        model.moveProvider(.grok, to: .claude)
        XCTAssertEqual(model.providerOrder, [.piAgent, .codex, .claude, .grok])
        model.moveProvider(.grok, to: .grok)
        XCTAssertEqual(
            UsageModel(usageService: UsageService(), defaults: defaults).providerOrder,
            [.piAgent, .codex, .claude, .grok]
        )
    }
}
