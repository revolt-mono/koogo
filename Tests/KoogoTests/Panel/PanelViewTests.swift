import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class PanelViewTests: XCTestCase {
    @MainActor
    func testQuotaPreferencesGateProvidersIndependentlyWithoutDisablingUsage() async throws {
        let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
        try workspace.write(codexLog(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
        let defaults = try makeIsolatedDefaults()
        let update = UpdateModel()
        let reminder = BreakReminderModel(notifications: PanelTestNotifications(), defaults: defaults)
        let inbox = InboxModel(defaults: defaults)

        // Recreate the panel so each open reads the persisted choice, including the default-on case.
        let choices: [(Bool?, Bool?, Bool?)] = [
            (nil, nil, nil),
            (true, false, false), (false, true, false), (false, false, true),
            (false, false, false), (true, true, true),
        ]
        for (fetchCodex, fetchClaude, fetchGrok) in choices {
            defaults.set(fetchCodex, forKey: "fetch-codex-quota")
            defaults.set(fetchClaude, forKey: "fetch-claude-quota")
            defaults.set(fetchGrok, forKey: "fetch-grok-quota")
            let usage = UsageModel(
                usageService: UsageService(locations: workspace.locations, calendar: usageTestCalendar),
                defaults: defaults,
                now: { usageTestTimestamp }
            )
            let codex = CodexQuotaModel(quotaService: CodexQuotaService(executableCandidates: []))
            let claude = ClaudeQuotaModel(quotaService: ClaudeQuotaService(executableCandidates: []))
            let grok = GrokQuotaModel(
                quotaService: GrokQuotaService(authURL: workspace.root.appending(path: "missing"))
            )
            let host = NSHostingView(
                rootView: PanelView()
                    .defaultAppStorage(defaults)
                    .environment(usage)
                    .environment(codex)
                    .environment(claude)
                    .environment(grok)
                    .environment(update)
                    .environment(reminder)
                    .environment(inbox)
            )
            host.layoutSubtreeIfNeeded()
            try await waitUntil { usage.snapshot != nil }
            XCTAssertEqual(usage.snapshot?.providers[.codex]?.today.processedTokens, 1_000)

            try await waitUntil { !codex.isBusy && !claude.isRefreshing && !grok.isRefreshing }
            XCTAssertEqual(codex.state, fetchCodex ?? true ? .unavailable(.binaryNotFound) : .loading)
            XCTAssertEqual(claude.state, fetchClaude ?? true ? .unavailable(.binaryNotFound) : .loading)
            XCTAssertEqual(grok.state, fetchGrok ?? true ? .unavailable(.signedOut) : .loading)
            withExtendedLifetime(host) {}
        }
    }
}

@MainActor
private final class PanelTestNotifications: BreakReminderNotifications {
    func schedule(after _: TimeInterval) async throws(BreakReminderIssue) {}
    func hasDeliverableReminder() async -> Bool { false }
    func cancel() {}
}
