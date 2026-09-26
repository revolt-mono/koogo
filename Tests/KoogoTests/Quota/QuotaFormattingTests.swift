import Foundation
import XCTest

@testable import Koogo

final class QuotaFormattingTests: XCTestCase {
    func testTimeRemainingIncludesTheNextSmallerUnit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(TimeInterval, String)] = [
            (2 * 86_400 + 6 * 3_600 + 59 * 60, "in 2d 6h"),
            (2 * 86_400, "in 2d"),
            (86_400, "in 1d"),
            (86_399, "in 23h 59m"),
            (23 * 3_600, "in 23h"),
            (3_600 + 60, "in 1h 1m"),
            (3_600, "in 1h"),
            (59 * 60, "in 59m"),
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
