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

        XCTAssertEqual(try XCTUnwrap(model.snapshot).providers[.codex]?.today.processedTokens, 120)

        date.addTimeInterval(86_400)
        model.refresh()
        XCTAssertEqual(clockReads, 2)
        deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot?.providers[.codex]?.today.processedTokens == 120, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try XCTUnwrap(model.snapshot).providers[.codex]?.today.processedTokens, 0)
        XCTAssertEqual(try XCTUnwrap(model.snapshot).providers[.codex]?.month.processedTokens, 120)
    }

    func testDisabledProviderPersistsAndLeavesSnapshotEvenMidRefresh() async throws {
        let workspace = try UsageTestWorkspace()
        defer {
            try? workspace.remove()
        }
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let suiteName = "UsageModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let model = UsageModel(
            usageService: UsageService(locations: workspace.locations, calendar: workspace.calendar),
            defaults: defaults,
            now: { usageTestTimestamp }
        )

        model.refresh()
        model.setEnabled(false, for: .codex)
        let deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot?.providers[.codex] != nil || model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(Set(snapshot.providers.keys), [.claude, .piAgent, .grok])
        XCTAssertEqual(snapshot.summary.today.current.processedTokens, 0)
        XCTAssertEqual(
            UsageModel(usageService: UsageService(), defaults: defaults).enabledProviders,
            [.claude, .piAgent, .grok]
        )
    }

    func testRefreshSkipsProvidersWithoutHomeUntilTheyAppear() async throws {
        let workspace = try UsageTestWorkspace()
        defer {
            try? workspace.remove()
        }
        let grokHome = workspace.root.appending(path: "grok")
        try FileManager.default.removeItem(at: grokHome)
        let suiteName = "UsageModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let model = UsageModel(
            usageService: UsageService(locations: workspace.locations, calendar: workspace.calendar),
            defaults: defaults,
            now: { usageTestTimestamp }
        )

        model.refresh()
        XCTAssertEqual(model.activeProviders, [.codex, .claude, .piAgent])
        var deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), [.codex, .claude, .piAgent])

        try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
        model.refresh()
        XCTAssertEqual(model.activeProviders, Set(UsageProvider.allCases))
        deadline = ContinuousClock.now + .seconds(1)
        while model.snapshot?.providers[.grok] == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(Set(try XCTUnwrap(model.snapshot).providers.keys), Set(UsageProvider.allCases))
    }
}
