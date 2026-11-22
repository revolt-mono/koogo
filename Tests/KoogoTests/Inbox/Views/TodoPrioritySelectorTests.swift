import AppKit
import SwiftUI
import Testing

@testable import Koogo

@MainActor
struct TodoPrioritySelectorTests {
  @Test
  func `clicking a dot selects its priority`() throws {
    let selection = SelectionBox(.urgent)
    let window = hostingWindow(selection)
    defer { window.orderOut(nil) }

    try send(.leftMouseDown, at: CGPoint(x: 11, y: 11), in: window)
    try send(.leftMouseUp, at: CGPoint(x: 11, y: 11), in: window)

    #expect(selection.value == .backlog)
  }

  @Test
  func `dragging selects the option under the pointer`() throws {
    let selection = SelectionBox(.urgent)
    let window = hostingWindow(selection)
    defer { window.orderOut(nil) }

    try send(.leftMouseDown, at: CGPoint(x: 110, y: 11), in: window)
    try send(.leftMouseDragged, at: CGPoint(x: 63, y: 11), in: window)
    #expect(selection.value == .urgent)
    try send(.leftMouseDragged, at: CGPoint(x: 41, y: 11), in: window)
    #expect(selection.value == .normal)
    try send(.leftMouseDragged, at: CGPoint(x: 190, y: 11), in: window)
    try send(.leftMouseUp, at: CGPoint(x: 190, y: 11), in: window)

    #expect(selection.value == .urgent)
  }

  private func hostingWindow(_ selection: SelectionBox) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: -100_000, y: -100_000, width: 200, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false,
    )
    window.contentView = NSHostingView(
      rootView: TodoPrioritySelector(
        selection: Binding {
          selection.value
        } set: {
          selection.value = $0
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    )
    window.contentView?.layoutSubtreeIfNeeded()
    // swiftui ignores mouse events in a window that was never ordered in.
    window.orderFrontRegardless()
    return window
  }

  private func send(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws {
    let height = try #require(window.contentView).bounds.height
    window.sendEvent(
      try #require(
        NSEvent.mouseEvent(
          with: type,
          location: CGPoint(x: point.x, y: height - point.y),
          modifierFlags: [],
          timestamp: 0,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: 0,
          clickCount: 1,
          pressure: 0,
        )
      )
    )
  }
}

@MainActor
private final class SelectionBox {
  init(_ value: TodoPriority) {
    self.value = value
  }

  var value: TodoPriority
}
