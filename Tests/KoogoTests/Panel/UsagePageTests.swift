import AppKit
import SwiftUI
import Testing

@testable import Koogo

struct UsagePageTests {
  @Test @MainActor
  func `a hidden usage page reads only never read quota until shown`() async throws {
    let workspace = try UsageTestWorkspace()
    let failed = QuotaReading.unavailable(.sessionFailed)
    let models = AppModels(
      defaults: try scratch.makeIsolatedDefaults(),
      pipeline: workspace.makePipeline(),
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
    #expect(quota.statuses[.claude] == launchReading)

    host.rootView = UsagePage(maxHeight: 600, isShown: true).sceneRoot(models)
    host.layoutSubtreeIfNeeded()
    try await Poll.until { quota.statuses[.claude] != launchReading && !quota.statuses[.claude].isBusy }
  }

  private let scratch = Scratch()
}
