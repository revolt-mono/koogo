import XCTest

@testable import Koogo

final class QuotaSectionTests: XCTestCase {
    func testTimeRemainingIncludesTheNextSmallerUnit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(TimeInterval, String)] = [
            (2 * 86_400 + 6 * 3_600 + 59 * 60, "in 2d 6h"),
            (60, "in 1m"),
            (59, "soon"),
            (-1, "soon"),
        ]

        for (interval, expected) in cases {
            XCTAssertEqual(
                quotaTimeRemainingText(until: now.addingTimeInterval(interval), now: now),
                expected
            )
        }
    }
}
