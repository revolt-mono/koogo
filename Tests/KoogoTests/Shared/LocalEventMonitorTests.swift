import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class LocalEventMonitorTests: XCTestCase {
  @MainActor
  func testDismantledMonitorReleasesItsHandler() async throws {
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
      XCTAssertFalse(host.subviews.isEmpty, "expected the monitor view to be mounted")
    }
    try await Poll.until { owner == nil }
  }

  private final class Owner { }
}
