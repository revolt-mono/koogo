import ApplicationServices
import XCTest

@testable import Koogo

@MainActor
final class EventTapTests: XCTestCase {
    /// macOS calls back on the tap's own thread, never the main actor.
    func testCallbackRewritesNotchesOffTheMainActor() async throws {
        let tap = EventTap()
        nonisolated(unsafe) let userInfo = Unmanaged.passUnretained(tap).toOpaque()
        nonisolated(unsafe) let event = try XCTUnwrap(
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)
        )

        let delivered = await Task.detached {
            EventTap.callback(OpaquePointer(bitPattern: 1)!, .scrollWheel, event, userInfo)?
                .takeUnretainedValue()
                .getIntegerValueField(.scrollWheelEventDeltaAxis1)
        }.value

        XCTAssertEqual(delivered, -2)
        withExtendedLifetime(tap) {}
    }
}
