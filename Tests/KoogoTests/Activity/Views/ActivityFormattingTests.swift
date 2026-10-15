import XCTest

@testable import Koogo

final class ActivityFormattingTests: XCTestCase {
    func testBytesSwitchUnitsAtAGigabyte() {
        XCTAssertEqual(Measure(bytes: 22_752_738_181).text, "21.19 GB")
        XCTAssertEqual(Measure(bytes: 1 << 30).text, "1.00 GB")
        XCTAssertEqual(Measure(bytes: 956_301_312).text, "912 MB")
        XCTAssertEqual(Measure(bytes: 0).text, "0 MB")
    }

    func testPercentRoundsToWholeNumbers() {
        XCTAssertEqual(Measure(fraction: 0.314).text, "31%")
        XCTAssertEqual(Measure(fraction: 0.005).value, "1")
        XCTAssertEqual(Measure(fraction: 1).text, "100%")
    }

    func testWattsKeepOneDecimal() {
        XCTAssertEqual(Measure(watts: 14.26).text, "14.3 W")
        XCTAssertEqual(Measure(watts: 0).value, "0.0")
    }
}
