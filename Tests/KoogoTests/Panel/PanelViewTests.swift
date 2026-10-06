import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class PanelViewTests: XCTestCase {
    @MainActor
    func testOpeningThePanelRefreshesUsageAndQuotaForEveryShownProviderWithQuotaOn() async throws {
        let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
        try workspace.write(codexLog(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
        let defaults = try makeIsolatedDefaults()
        let update = UpdateModel()
        let reminder = BreakReminderModel(notifications: BreakReminderTestNotifications(), defaults: defaults)
        let inbox = InboxModel(defaults: defaults)

        let choices: [Set<QuotaProvider>] = [
            [], [.codex], [.claude], [.grok], [.claude, .grok], [.codex, .claude, .grok],
        ]
        for disabled in choices {
            let preferences = ProviderPreferences(defaults: try makeIsolatedDefaults())
            for provider in disabled {
                preferences.setQuota(false, for: provider)
            }
            preferences.setUsage(false, for: .codex)
            let usage = UsageModel(
                pipeline: UsagePipeline(home: workspace.root, calendar: usageTestCalendar),
                now: { usageTestTimestamp }
            )
            let quota = QuotaModel(
                codex: CodexQuotaSource(executableCandidates: []),
                claude: ClaudeQuotaSource(executableCandidates: []),
                grok: GrokQuotaSource(executableCandidates: [])
            )
            let host = NSHostingView(
                rootView: PanelView()
                    .environment(preferences)
                    .environment(usage)
                    .environment(quota)
                    .environment(update)
                    .environment(reminder)
                    .environment(inbox)
            )
            host.layoutSubtreeIfNeeded()
            try await waitUntil { usage.snapshot != nil }
            XCTAssertNil(usage.snapshot?.providers[.codex])
            XCTAssertEqual(usage.snapshot?.providers[.claude]?.periods[.today].total.processedTokens, 0)

            try await waitUntil { QuotaProvider.allCases.allSatisfy { !quota.isBusy($0) } }
            for provider in QuotaProvider.allCases {
                let isShown = provider != .codex && !disabled.contains(provider)
                let expected: QuotaReading? = isShown ? .unavailable(.binaryNotFound) : nil
                XCTAssertEqual(quota.statuses[provider].latest, expected, "\(provider)")
            }
            withExtendedLifetime(host) {}
        }
    }
}
