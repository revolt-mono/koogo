import AppKit
import XCTest

@testable import Koogo

final class PopoverClickBoundaryTests: XCTestCase {
    @MainActor
    func testEachTriggerPressIsIndependentAndPreservesEventMetadata() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            for count in [2, 3, 6] {
                let original = try fixture.event(type: type, count: count)
                let result = PopoverClickBoundary.independentClick(original, in: fixture.anchor)

                XCTAssertEqual(original.clickCount, count)
                XCTAssertEqual(result.clickCount, 1)
                XCTAssertEqual(result.type, original.type)
                XCTAssertEqual(result.locationInWindow, original.locationInWindow)
                XCTAssertEqual(result.windowNumber, original.windowNumber)
                XCTAssertEqual(result.eventNumber, original.eventNumber)
                XCTAssertEqual(result.timestamp, original.timestamp)
                XCTAssertEqual(result.modifierFlags, original.modifierFlags)
                XCTAssertEqual(result.pressure, original.pressure)
                XCTAssertEqual(result.buttonNumber, original.buttonNumber)
            }
        }
    }

    @MainActor
    func testSingleClicksPassThroughUnchanged() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let original = try fixture.event(count: 1)
        XCTAssertTrue(PopoverClickBoundary.independentClick(original, in: fixture.anchor) === original)
    }

    @MainActor
    func testDoubleClicksOutsideTheTriggerAreUntouched() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let original = try fixture.event(location: NSPoint(x: 250, y: 150))
        XCTAssertTrue(PopoverClickBoundary.independentClick(original, in: fixture.anchor) === original)
    }

    @MainActor
    func testAnotherWindowsClicksAreUntouchedEvenAtTheSameCoordinates() throws {
        let fixture = Fixture()
        let other = Fixture()
        defer {
            fixture.window.close()
            other.window.close()
        }
        let original = try other.event()
        XCTAssertTrue(PopoverClickBoundary.independentClick(original, in: fixture.anchor) === original)
    }

    @MainActor
    func testHiddenAndDetachedTriggersCannotChangeEvents() throws {
        let fixture = Fixture()
        defer { fixture.window.close() }
        let original = try fixture.event()
        fixture.anchor.isHidden = true
        XCTAssertTrue(PopoverClickBoundary.independentClick(original, in: fixture.anchor) === original)
        fixture.anchor.isHidden = false
        fixture.anchor.removeFromSuperview()
        XCTAssertTrue(PopoverClickBoundary.independentClick(original, in: fixture.anchor) === original)
    }
}

@MainActor
private struct Fixture {
    let window: NSWindow
    let anchor: NSView

    init() {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        anchor = NSView(frame: NSRect(x: 40, y: 30, width: 100, height: 40))
        window.contentView?.addSubview(anchor)
        window.orderFront(nil)
    }

    func event(
        type: NSEvent.EventType = .leftMouseDown,
        count: Int = 2,
        location: NSPoint = NSPoint(x: 70, y: 40)
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [.shift],
                timestamp: 123,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 42,
                clickCount: count,
                pressure: 0.5
            )
        )
    }
}
