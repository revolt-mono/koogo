import AppKit
import SwiftUI
import Testing

@testable import Koogo

struct PanelViewTests {
  @Test @MainActor
  func `opening the panel refreshes usage and quota for every shown provider and samples no activity`() async throws {
    let workspace = try UsageTestWorkspace()
    try workspace.write(CodexLog.session(input: 700, output: 300), to: workspace.codexSessions.appending(path: "log.jsonl"))
    let defaults = try scratch.makeIsolatedDefaults()
    let activitySamples = Counter()

    let models = AppModels(
      defaults: defaults,
      pipeline: workspace.makePipeline(),
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
    #expect(usage.snapshot?.providers[.codex] == nil)
    #expect(usage.snapshot?.todayTokens(.claude) == 0)

    try await Poll.until { QuotaProvider.allCases.allSatisfy { !quota.statuses[$0].isBusy } }
    #expect(quota.statuses[.codex] == .unread)
    #expect(quota.statuses[.claude].latest == .unavailable(.binaryNotFound))
    #expect(quota.statuses[.grok].latest == .unavailable(.binaryNotFound))
    #expect(activitySamples.value == 0)
  }

  private let scratch = Scratch()
}
