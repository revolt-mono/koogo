import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class UsagePageTests: XCTestCase {
  @MainActor
  func testAHiddenUsagePageReadsOnlyNeverReadQuotaUntilShown() async throws {
    let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
    let failed = QuotaReading.unavailable(.sessionFailed)
    let models = AppModels(
      defaults: try makeIsolatedDefaults(),
      pipeline: UsagePipeline(home: workspace.root, calendar: UsageFixture.calendar),
      quotaSources: QuotaSources(
        codex: ScriptedQuotaSource([failed, failed]),
        claude: ScriptedQuotaSource([failed, failed]),
        grok: ScriptedQuotaSource([failed, failed]),
      ),
      breakNotifications: BreakReminderTestNotifications(),
      activitySample: { ActivitySample.stub() },
      isInstalled: { _ in false },
      now: { UsageFixture.timestamp },
    )
    let quota = models.quota
    models.preferences[isUsageEnabled: .codex] = false
    quota.refresh(models.preferences.quotaProviders)
    try await Poll.until { quota.statuses[.claude].latest != nil && quota.statuses[.grok].latest != nil }
    let launchReading = quota.statuses[.claude]
    models.preferences[isUsageEnabled: .codex] = true

    let host = NSHostingView(rootView: UsagePage(maxHeight: 600, isShown: false).sceneRoot(models))
    host.layoutSubtreeIfNeeded()
    try await Poll.until { quota.statuses[.codex].latest != nil }
    XCTAssertEqual(quota.statuses[.claude], launchReading)

    host.rootView = UsagePage(maxHeight: 600, isShown: true).sceneRoot(models)
    host.layoutSubtreeIfNeeded()
    try await Poll.until { quota.statuses[.claude] != launchReading && !quota.statuses[.claude].isBusy }
  }
}
