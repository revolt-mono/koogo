import AppKit
import SwiftUI
import XCTest

@testable import Koogo

@MainActor
final class PointerTrackingTests: XCTestCase {
    func testReportsMovesInTopLeftLocalSpaceAndCrossesOnce() throws {
        var phases: [HoverPhase] = []
        let window = hostingWindow(Color.clear.onContinuousPointerHover { phases.append($0) })
        let tracker = try XCTUnwrap(window.contentView.map(innermostView))

        tracker.mouseEntered(with: try crossing(.mouseEntered, at: CGPoint(x: 10, y: 40), in: window))
        tracker.mouseEntered(with: try crossing(.mouseEntered, at: CGPoint(x: 20, y: 40), in: window))
        tracker.mouseMoved(
            with: try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: .mouseMoved,
                    location: CGPoint(x: 30, y: 20),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 0,
                    pressure: 0
                )
            )
        )
        tracker.mouseExited(with: try crossing(.mouseExited, at: CGPoint(x: 30, y: 60), in: window))
        tracker.mouseExited(with: try crossing(.mouseExited, at: CGPoint(x: 30, y: 60), in: window))

        XCTAssertEqual(phases, [.active(CGPoint(x: 10, y: 10)), .active(CGPoint(x: 30, y: 30)), .ended])
    }

    func testTracksNoFurtherThanTheViewInsideALargerHost() throws {
        let window = hostingWindow(Color.clear.frame(width: 20, height: 10).onPointerHover { _ in })
        let tracker = try XCTUnwrap(window.contentView.map(innermostView))

        XCTAssertEqual(tracker.visibleRect, tracker.bounds)
    }

    private func hostingWindow(_ root: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 50),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: root)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private func crossing(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )
        )
    }

    private func innermostView(in view: NSView) -> NSView {
        view.subviews.first.map(innermostView) ?? view
    }
}
