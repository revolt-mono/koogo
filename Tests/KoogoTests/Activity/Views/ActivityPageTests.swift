import AppKit
import SwiftUI
import Testing

@testable import Koogo

struct ActivityPageTests {
  @Test @MainActor
  func `sampling runs while the page is shown and stops once it leaves`() async throws {
    let calls = Counter()
    let model = ActivityModel(interval: .milliseconds(1)) {
      calls.increment()
      return ActivitySample.stub()
    }
    let host = NSHostingView(rootView: ActivityPage(isShown: true).environment(model))
    host.layoutSubtreeIfNeeded()

    try await Poll.until { model.cpuTrend.count >= 3 }

    host.rootView = ActivityPage(isShown: false).environment(model)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(20))
    let settled = calls.value
    try await Task.sleep(for: .milliseconds(30))
    #expect(calls.value == settled)
  }
}
