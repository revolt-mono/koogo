import AppKit
import Testing

@testable import Koogo

@MainActor
struct PanelDisclosureTests {
  @Test
  func `each trigger press is independent and preserves event metadata`() throws {
    let fixture = Fixture()
    defer { fixture.window.close() }
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      for count in [2, 3, 6] {
        let original = try fixture.event(type: type, count: count)
        let result = original.independentClick(in: fixture.anchor)

        #expect(result.clickCount == 1)
        #expect(result.type == original.type)
        #expect(result.locationInWindow == original.locationInWindow)
        #expect(result.windowNumber == original.windowNumber)
        #expect(result.eventNumber == original.eventNumber)
        #expect(result.timestamp == original.timestamp)
        #expect(result.modifierFlags == original.modifierFlags)
        #expect(result.pressure == original.pressure)
      }
    }
  }

  @Test
  func `single clicks pass through unchanged`() throws {
    let fixture = Fixture()
    defer { fixture.window.close() }
    let original = try fixture.event(count: 1)
    #expect(original.independentClick(in: fixture.anchor) === original)
  }

  @Test
  func `double clicks outside the trigger are untouched`() throws {
    let fixture = Fixture()
    defer { fixture.window.close() }
    let original = try fixture.event(location: NSPoint(x: 250, y: 150))
    #expect(original.independentClick(in: fixture.anchor) === original)
  }

  @Test
  func `another windows clicks are untouched even at the same coordinates`() throws {
    let fixture = Fixture()
    let other = Fixture()
    defer {
      fixture.window.close()
      other.window.close()
    }
    let original = try other.event()
    #expect(original.independentClick(in: fixture.anchor) === original)
  }

  @Test
  func `hidden and detached triggers cannot change events`() throws {
    let fixture = Fixture()
    defer { fixture.window.close() }
    let original = try fixture.event()
    fixture.anchor.isHidden = true
    #expect(original.independentClick(in: fixture.anchor) === original)
    fixture.anchor.isHidden = false
    fixture.anchor.removeFromSuperview()
    #expect(original.independentClick(in: fixture.anchor) === original)
  }
}

@MainActor
private struct Fixture {
  init() {
    _ = NSApplication.shared
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: .borderless,
      backing: .buffered,
      defer: false,
    )
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    anchor = NSView(frame: NSRect(x: 40, y: 30, width: 100, height: 40))
    window.contentView?.addSubview(anchor)
    window.orderFront(nil)
  }

  let window: NSWindow
  let anchor: NSView

  func event(
    type: NSEvent.EventType = .leftMouseDown,
    count: Int = 2,
    location: NSPoint = NSPoint(x: 70, y: 40),
  ) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [.shift],
        timestamp: 123,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 42,
        clickCount: count,
        pressure: 0.5,
      )
    )
  }
}
