import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaFormattingTests: XCTestCase {
    func testTimeRemainingUsesLargestAllowedUnit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(TimeInterval, String)] = [
            (2 * 86_400, "in 2 days"),
            (86_400, "in 1 day"),
            (23 * 3_600, "in 23h"),
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
