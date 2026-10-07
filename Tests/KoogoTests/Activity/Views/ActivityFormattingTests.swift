import XCTest

@testable import Koogo

final class ActivityFormattingTests: XCTestCase {
    func testBytesSwitchUnitsAtAGigabyte() {
        XCTAssertEqual(ActivityFormatting.bytes(22_752_738_181).text, "21.19 GB")
        XCTAssertEqual(ActivityFormatting.bytes(1 << 30).text, "1.00 GB")
        XCTAssertEqual(ActivityFormatting.bytes(956_301_312).text, "912 MB")
        XCTAssertEqual(ActivityFormatting.bytes(0).text, "0 MB")
    }

    func testPercentRoundsToWholeNumbers() {
        XCTAssertEqual(ActivityFormatting.percent(0.314).text, "31%")
        XCTAssertEqual(ActivityFormatting.percent(0.005).value, "1")
        XCTAssertEqual(ActivityFormatting.percent(1).text, "100%")
    }
}
