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

        let models = AppModels(
            defaults: defaults,
            pipeline: UsagePipeline(home: workspace.root, calendar: usageTestCalendar),
            quotaSources: .missingExecutables,
            breakNotifications: BreakReminderTestNotifications(),
            activitySample: {
                activitySamples.increment()
                return activitySample()
            },
            isInstalled: { _ in false },
            now: { usageTestTimestamp }
        )
        models.preferences[usage: .codex] = false
        let usage = models.usage
        let quota = models.quota
        let host = NSHostingView(rootView: PanelView().sceneRoot(models))
        host.layoutSubtreeIfNeeded()
        try await waitUntil { usage.snapshot != nil }
        XCTAssertNil(usage.snapshot?.providers[.codex])
        XCTAssertEqual(usage.snapshot?.todayTokens(.claude), 0)

        try await waitUntil { QuotaProvider.allCases.allSatisfy { !quota.statuses[$0].isBusy } }
        XCTAssertEqual(quota.statuses[.codex], .unread)
        XCTAssertEqual(quota.statuses[.claude].latest, .unavailable(.binaryNotFound))
        XCTAssertEqual(quota.statuses[.grok].latest, .unavailable(.binaryNotFound))
        XCTAssertEqual(activitySamples.value, 0)
        withExtendedLifetime(host) {}
    }

    @MainActor
    func testAHiddenUsagePageReadsOnlyNeverReadQuotaUntilShown() async throws {
        let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
        let failed = QuotaReading.unavailable(.sessionFailed)
        let models = AppModels(
            defaults: try makeIsolatedDefaults(),
            pipeline: UsagePipeline(home: workspace.root, calendar: usageTestCalendar),
            quotaSources: QuotaSources(
                codex: ScriptedQuotaSource([failed, failed]),
                claude: ScriptedQuotaSource([failed, failed]),
                grok: ScriptedQuotaSource([failed, failed])
            ),
            breakNotifications: BreakReminderTestNotifications(),
            activitySample: { activitySample() },
            isInstalled: { _ in false },
            now: { usageTestTimestamp }
        )
        let quota = models.quota
        models.preferences[usage: .codex] = false
        quota.refresh(models.preferences.quotaProviders)
        try await waitUntil { quota.statuses[.claude].latest != nil && quota.statuses[.grok].latest != nil }
        let launchReading = quota.statuses[.claude]
        models.preferences[usage: .codex] = true

        let host = NSHostingView(rootView: UsagePage(maxHeight: 600, isShown: false).sceneRoot(models))
        host.layoutSubtreeIfNeeded()
        try await waitUntil { quota.statuses[.codex].latest != nil }
        XCTAssertEqual(quota.statuses[.claude], launchReading)

        host.rootView = UsagePage(maxHeight: 600, isShown: true).sceneRoot(models)
        host.layoutSubtreeIfNeeded()
        try await waitUntil { quota.statuses[.claude] != launchReading && !quota.statuses[.claude].isBusy }
        withExtendedLifetime(host) {}
    }
}
