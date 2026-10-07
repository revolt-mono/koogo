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
        let activity = ActivityModel { activitySample() }

        for disabled: Set<QuotaProvider> in [
            [], [.codex], [.claude], [.grok], [.claude, .grok], [.codex, .claude, .grok],
        ] {
            let preferences = ProviderPreferences(defaults: try makeIsolatedDefaults())
            for provider in disabled {
                preferences.setQuota(false, for: provider)
            }
            preferences.setUsage(false, for: .codex)
            let pipeline = UsagePipeline(home: workspace.root, calendar: usageTestCalendar)
            let usage = UsageModel(pipeline: pipeline, now: { usageTestTimestamp })
            let quota = QuotaModel(
                sources: QuotaSources(
                    codex: CodexQuotaSource(executableCandidates: []),
                    claude: ClaudeQuotaSource(executableCandidates: []),
                    grok: GrokQuotaSource(executableCandidates: [])
                )
            )
            let host = NSHostingView(
                rootView: PanelView().environment(
                    AppModels(
                        preferences: preferences,
                        usage: usage,
                        quota: quota,
                        codexReset: CodexQuotaResetModel(quota: quota),
                        update: UpdateModel(),
                        breakReminder: BreakReminderModel(
                            notifications: BreakReminderTestNotifications(),
                            defaults: defaults
                        ),
                        inbox: InboxModel(defaults: defaults),
                        activity: activity
                    )
                )
            )
            host.layoutSubtreeIfNeeded()
            try await waitUntil { usage.snapshot != nil && activity.latest != nil }
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
