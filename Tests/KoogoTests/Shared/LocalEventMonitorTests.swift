import AppKit
import SwiftUI
import Testing

@testable import Koogo

struct LocalEventMonitorTests {
  @Test @MainActor
  func `dismantled monitor releases its handler`() async throws {
    weak var owner: Owner?
    do {
      let captured = Owner()
      owner = captured
      let host = NSHostingView(
        rootView: Color.clear.onLocalEvent(.keyDown) { event, _ in
          withExtendedLifetime(captured) { event }
        }
      )
      host.layoutSubtreeIfNeeded()
      #expect(!host.subviews.isEmpty, "expected the monitor view to be mounted")
    }
    try await Poll.until { owner == nil }
  }

  private final class Owner { }
}
