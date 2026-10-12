import AppKit
import XCTest

@testable import Koogo

final class WheelPagingTests: XCTestCase {
    func testWheelClicksStepWhenSidewaysPassWhenVerticalAndDropWhenTilted() {
        XCTAssertEqual(WheelPaging(deltaX: -3, deltaY: 0), .step(1))
        XCTAssertEqual(WheelPaging(deltaX: 3, deltaY: 0), .step(-1))
        XCTAssertEqual(WheelPaging(deltaX: 0, deltaY: 0), .pass)
        XCTAssertEqual(WheelPaging(deltaX: 0, deltaY: 3), .pass)
        XCTAssertEqual(WheelPaging(deltaX: 3, deltaY: 3), .drop)
    }

    func testOnlyPhaselessEventsCountAsClicks() {
        XCTAssertEqual(WheelPaging(sideways(-3)), .step(1))
        XCTAssertEqual(WheelPaging(sideways(-30, phase: .changed)), .pass)
    }

    private func sideways(_ deltaX: Int32, phase: NSEvent.Phase = []) -> NSEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 0,
            wheel2: deltaX,
            wheel3: 0
        )!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return NSEvent(cgEvent: event)!
    }
}
