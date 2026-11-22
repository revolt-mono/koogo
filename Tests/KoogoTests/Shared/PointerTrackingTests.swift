import AppKit
import SwiftUI
import Testing

@testable import Koogo

@MainActor
struct PointerTrackingTests {
  @Test
  func `reports moves in top left local space and crosses once`() throws {
    var phases = [HoverPhase]()
    let window = hostingWindow(Color.clear.onContinuousPointerHover { phases.append($0) })
    let tracker = try #require(window.contentView.map(innermostView))

    tracker.mouseEntered(with: try crossing(.mouseEntered, at: CGPoint(x: 10, y: 40), in: window))
    tracker.mouseEntered(with: try crossing(.mouseEntered, at: CGPoint(x: 20, y: 40), in: window))
    tracker.mouseMoved(
      with: try #require(
        NSEvent.mouseEvent(
          with: .mouseMoved,
          location: CGPoint(x: 30, y: 20),
          modifierFlags: [],
          timestamp: 0,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: 0,
          clickCount: 0,
          pressure: 0,
        )
      )
    )
    tracker.mouseExited(with: try crossing(.mouseExited, at: CGPoint(x: 30, y: 60), in: window))
    tracker.mouseExited(with: try crossing(.mouseExited, at: CGPoint(x: 30, y: 60), in: window))

    #expect(phases == [.active(CGPoint(x: 10, y: 10)), .active(CGPoint(x: 30, y: 30)), .ended])
  }

  @Test
  func `tracks no further than the view inside a larger host`() throws {
    let window = hostingWindow(Color.clear.frame(width: 20, height: 10).onPointerHover { _ in })
    let tracker = try #require(window.contentView.map(innermostView))

    #expect(tracker.visibleRect.size == CGSize(width: 20, height: 10))
  }

  /// the window sits off every screen so the real cursor cannot enter the tracker during layout.
  private func hostingWindow(_ root: some View) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: -100_000, y: -100_000, width: 100, height: 50),
      styleMask: .borderless,
      backing: .buffered,
      defer: false,
    )
    window.contentView = NSHostingView(rootView: root)
    window.contentView?.layoutSubtreeIfNeeded()
    return window
  }

  private func crossing(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws -> NSEvent {
    try #require(
      NSEvent.enterExitEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil,
      )
    )
  }

  private func innermostView(in view: NSView) -> NSView {
    view.subviews.first.map(innermostView) ?? view
  }
}
