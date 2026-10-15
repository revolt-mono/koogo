import XCTest

@testable import Koogo

final class DisplayLocaleTests: XCTestCase {
    func testUnitsShowTwoWholeUnitsAtMost() {
        XCTAssertEqual(Duration.seconds(80 * 60).formatted(.displayUnits(allowed: [.hours, .minutes])), "1h 20m")
        XCTAssertEqual(Duration.seconds(45 * 60 + 30).formatted(.displayUnits(allowed: [.hours, .minutes])), "45m")
        XCTAssertEqual(
            Duration.seconds(26 * 60 * 60 + 5 * 60).formatted(.displayUnits(allowed: [.days, .hours, .minutes])),
            "1d 2h"
        )
    }
}
