import AppKit
import XCTest

@testable import Koogo

final class WheelPagingTests: XCTestCase {
    func testWheelClicksStepWhenSidewaysPassWhenVerticalAndDropWhenTilted() {
        XCTAssertEqual(WheelPaging(scrollEvent(horizontal: -3)), .step(1))
        XCTAssertEqual(WheelPaging(scrollEvent(horizontal: 3)), .step(-1))
        XCTAssertEqual(WheelPaging(scrollEvent()), .pass)
        XCTAssertEqual(WheelPaging(scrollEvent(vertical: 3)), .pass)
        XCTAssertEqual(WheelPaging(scrollEvent(horizontal: 3, vertical: 3)), .drop)
    }

    func testContinuousAndPhasedScrollingPassesThrough() {
        XCTAssertEqual(WheelPaging(scrollEvent(horizontal: -30, phase: .changed)), .pass)
        XCTAssertEqual(WheelPaging(scrollEvent(horizontal: -30, units: .pixel)), .pass)
    }

    private func scrollEvent(
        horizontal: Int32 = 0,
        vertical: Int32 = 0,
        phase: NSEvent.Phase = [],
        units: CGScrollEventUnit = .line
    ) -> NSEvent {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        )!
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return NSEvent(cgEvent: event)!
    }
}
