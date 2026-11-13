import XCTest

@testable import Koogo

final class ISO8601DateTests: XCTestCase {
  func testFractionalSecondsAndTimeZoneOffsets() throws {
    let whole = Date(timeIntervalSince1970: 1_787_659_200)
    for text in ["2026-08-25T12:00:00Z", "2026-08-25T14:00:00+02:00", "2026-08-25T07:00:00-05:00"] {
      XCTAssertEqual(Date(iso8601: text.utf8), whole, text)
    }
    for text in ["2026-08-25T12:00:00.125Z", "2026-08-25T14:00:00.125+02:00"] {
      let parsed = try XCTUnwrap(Date(iso8601: text.utf8), text)
      XCTAssertEqual(parsed.timeIntervalSince(whole), 0.125, accuracy: 0.000_001, text)
    }
  }

  func testFractionsOffsetsAndOldYearsMatchFoundation() {
    for text in [
      "2026-05-29T00:50:38.074Z",
      "2026-05-29T03:02:37.111+02:00",
      "2026-05-29T09:38:34.222123Z",
      "2026-05-29T00:00:00+18:00",
      "2026-05-29T00:00:00-18:00",
      "2026-05-29T00:00:00+18:01",
      "2026-05-29T00:00:00-19:00",
      "1582-10-10T00:00:00Z",
      "1500-02-29T00:00:00Z",
      "0001-01-01T00:00:00Z",
    ] {
      XCTAssertEqual(Date(iso8601: text.utf8), try? Date.ISO8601FormatStyle().parse(text), text)
    }
  }

  func testMalformedTimestampsAreRejected() {
    for text in ["", "not-a-date", "2026-08-25", "2026-08-25T12:00:00.", "2026-08-25T12:00:00+invalid"] {
      XCTAssertNil(Date(iso8601: text.utf8), text)
    }
  }
}
