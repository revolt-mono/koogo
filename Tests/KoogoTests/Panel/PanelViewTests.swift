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
}
