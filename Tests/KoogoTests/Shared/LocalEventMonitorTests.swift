import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class LocalEventMonitorTests: XCTestCase {
    private final class Owner {}

    @MainActor
    func testDismantledMonitorReleasesItsHandler() async throws {
        weak var owner: Owner?
        do {
            let captured = Owner()
            owner = captured
            let host = NSHostingView(
                rootView: LocalEventMonitor(events: .keyDown) { event, _ in
                    withExtendedLifetime(captured) { event }
                }
            )
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(host.subviews.isEmpty, "expected the monitor view to be mounted")
        }
        try await waitUntil { owner == nil }
    }
}
