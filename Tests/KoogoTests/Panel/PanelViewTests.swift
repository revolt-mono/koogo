import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class PanelViewTests: XCTestCase {
    @MainActor
    func testOpeningThePanelRefreshesUsageAndQuotaForEveryShownProviderAndSamplesNoActivity() async throws {
        let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
        try workspace.write(codexLog(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
        let defaults = try makeIsolatedDefaults()
        let activitySamples = Counter()
        let activity = ActivityModel {
            activitySamples.increment()
            return activitySample()
        }

        let preferences = ProviderPreferences(defaults: defaults)
        preferences[usage: .codex] = false
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
                panelModels(
                    preferences: preferences,
                    usage: usage,
                    quota: quota,
                    activity: activity,
                    defaults: defaults
                )
            )
        )
        host.layoutSubtreeIfNeeded()
        try await waitUntil { usage.snapshot != nil }
        XCTAssertNil(usage.snapshot?.providers[.codex])
        XCTAssertEqual(usage.snapshot?.providers[.claude]?.periods[.today].total.processedTokens, 0)

        try await waitUntil { QuotaProvider.allCases.allSatisfy { !quota.statuses[$0].isBusy } }
        XCTAssertEqual(quota.statuses[.codex], .unread)
        XCTAssertEqual(quota.statuses[.claude].latest, .unavailable(.binaryNotFound))
        XCTAssertEqual(quota.statuses[.grok].latest, .unavailable(.binaryNotFound))
        XCTAssertEqual(activitySamples.value, 0)
        withExtendedLifetime(host) {}
    }
}

@MainActor
private func panelModels(
    preferences: ProviderPreferences,
    usage: UsageModel,
    quota: QuotaModel,
    activity: ActivityModel,
    defaults: UserDefaults
) -> AppModels {
    AppModels(
        preferences: preferences,
        usage: usage,
        quota: quota,
        codexReset: CodexQuotaResetModel(quota: quota),
        update: UpdateModel(),
        breakReminder: BreakReminderModel(notifications: BreakReminderTestNotifications(), defaults: defaults),
        inbox: InboxModel(defaults: defaults),
        activity: activity,
        mouse: MouseModel(defaults: defaults, isInstalled: { _ in false })
    )
}
