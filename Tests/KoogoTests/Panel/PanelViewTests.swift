import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class PanelViewTests: XCTestCase {
  @MainActor
  func testOpeningThePanelRefreshesUsageAndQuotaForEveryShownProviderAndSamplesNoActivity() async throws {
    let workspace = try UsageTestWorkspace(root: makeTemporaryDirectory())
    try workspace.write(CodexLog.session(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
    let defaults = try makeIsolatedDefaults()
    let activitySamples = Counter()

    let models = AppModels(
      defaults: defaults,
      pipeline: UsagePipeline(home: workspace.root, calendar: UsageFixture.calendar),
      quotaSources: .missingExecutables,
      breakNotifications: BreakReminderTestNotifications(),
      activitySample: {
        activitySamples.increment()
        return ActivitySample.stub()
      },
      isInstalled: { _ in false },
      now: { UsageFixture.timestamp },
    )
    models.preferences[isUsageEnabled: .codex] = false
    let usage = models.usage
    let quota = models.quota
    let host = NSHostingView(rootView: PanelView().sceneRoot(models))
    host.layoutSubtreeIfNeeded()
    try await Poll.until { usage.snapshot != nil }
    XCTAssertNil(usage.snapshot?.providers[.codex])
    XCTAssertEqual(usage.snapshot?.todayTokens(.claude), 0)

    try await Poll.until { QuotaProvider.allCases.allSatisfy { !quota.statuses[$0].isBusy } }
    XCTAssertEqual(quota.statuses[.codex], .unread)
    XCTAssertEqual(quota.statuses[.claude].latest, .unavailable(.binaryNotFound))
    XCTAssertEqual(quota.statuses[.grok].latest, .unavailable(.binaryNotFound))
    XCTAssertEqual(activitySamples.value, 0)
  }
}
