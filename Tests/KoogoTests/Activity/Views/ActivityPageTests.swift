import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class ActivityPageTests: XCTestCase {
    @MainActor
    func testSamplingRunsWhileThePageIsShownAndStopsOnceItLeaves() async throws {
        let calls = Counter()
        let model = ActivityModel(interval: .milliseconds(1)) {
            calls.increment()
            return activitySample()
        }
        let host = NSHostingView(rootView: AnyView(ActivityPage().environment(model)))
        host.layoutSubtreeIfNeeded()

        try await waitUntil { model.samples.count >= 3 }

        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        let settled = calls.value
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.value, settled)
        withExtendedLifetime(host) {}
    }
}
