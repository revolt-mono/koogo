import Foundation
import XCTest

@testable import Koogo

final class ISO8601DateTests: XCTestCase {
    func testFractionalSecondsAndTimeZoneOffsets() throws {
        let whole = Date(timeIntervalSince1970: 1_787_659_200)
        for text in ["2026-08-25T12:00:00Z", "2026-08-25T14:00:00+02:00", "2026-08-25T07:00:00-05:00"] {
            XCTAssertEqual(Date(iso8601: text), whole, text)
        }
        for text in ["2026-08-25T12:00:00.125Z", "2026-08-25T14:00:00.125+02:00"] {
            let parsed = try XCTUnwrap(Date(iso8601: text), text)
            XCTAssertEqual(parsed.timeIntervalSince(whole), 0.125, accuracy: 0.000_001, text)
        }
    }

    func testMalformedTimestampsAreRejected() {
        for text in ["", "not-a-date", "2026-08-25", "2026-08-25T12:00:00.", "2026-08-25T12:00:00+invalid"] {
            XCTAssertNil(Date(iso8601: text), text)
        }
    }
}
