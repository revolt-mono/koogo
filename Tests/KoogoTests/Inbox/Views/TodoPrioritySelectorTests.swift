import AppKit
import SwiftUI
import XCTest

@testable import Koogo

@MainActor
final class TodoPrioritySelectorTests: XCTestCase {
    func testClickingADotSelectsItsPriority() throws {
        let selection = SelectionBox(.urgent)
        let window = hostingWindow(selection)

        try send(.leftMouseDown, at: CGPoint(x: 11, y: 11), in: window)
        try send(.leftMouseUp, at: CGPoint(x: 11, y: 11), in: window)

        XCTAssertEqual(selection.value, .backlog)
    }

    func testDraggingSelectsTheOptionUnderThePointer() throws {
        let selection = SelectionBox(.urgent)
        let window = hostingWindow(selection)

        try send(.leftMouseDown, at: CGPoint(x: 110, y: 11), in: window)
        try send(.leftMouseDragged, at: CGPoint(x: 63, y: 11), in: window)
        XCTAssertEqual(selection.value, .urgent)
        try send(.leftMouseDragged, at: CGPoint(x: 41, y: 11), in: window)
        XCTAssertEqual(selection.value, .normal)
        try send(.leftMouseDragged, at: CGPoint(x: 190, y: 11), in: window)
        try send(.leftMouseUp, at: CGPoint(x: 190, y: 11), in: window)

        XCTAssertEqual(selection.value, .urgent)
    }

    private func hostingWindow(_ selection: SelectionBox) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -100_000, y: -100_000, width: 200, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
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
        // swiftui ignores mouse events in a window that was never ordered in; this one stays off every screen.
        window.orderFrontRegardless()
        addTeardownBlock { window.orderOut(nil) }
        return window
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) throws {
        let height = try XCTUnwrap(window.contentView).bounds.height
        window.sendEvent(
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type,
                    location: CGPoint(x: point.x, y: height - point.y),
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0
                )
            )
        )
    }
}

@MainActor
private final class SelectionBox {
    var value: TodoPriority

    init(_ value: TodoPriority) {
        self.value = value
    }
}
