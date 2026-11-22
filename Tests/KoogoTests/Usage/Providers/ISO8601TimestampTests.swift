import Foundation
import Testing

@testable import Koogo

struct ISO8601TimestampTests {
  @Test
  func `fractional seconds and time zone offsets`() throws {
    let whole = Date(timeIntervalSince1970: 1_787_659_200)
    for text in ["2026-08-25T12:00:00Z", "2026-08-25T14:00:00+02:00", "2026-08-25T07:00:00-05:00"] {
      #expect(UsageTimestamp(iso8601: text.utf8)?.date == whole, "\(text)")
    }
    for text in ["2026-08-25T12:00:00.125Z", "2026-08-25T14:00:00.125+02:00"] {
      let parsed = try #require(UsageTimestamp(iso8601: text.utf8), "\(text)")
      #expect(abs(parsed.date.timeIntervalSince(whole) - 0.125) < 0.000_001, "\(text)")
    }
  }

  @Test
  func `fractions offsets and old years match foundation`() {
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
      #expect(UsageTimestamp(iso8601: text.utf8)?.date == (try? Date.ISO8601FormatStyle().parse(text)), "\(text)")
    }
  }

  @Test
  func `malformed timestamps are rejected`() {
    for text in ["", "not-a-date", "2026-08-25", "2026-08-25T12:00:00.", "2026-08-25T12:00:00+invalid"] {
      #expect(UsageTimestamp(iso8601: text.utf8) == nil, "\(text)")
    }
  }

  @Test
  func `unix milliseconds match foundation`() {
    for milliseconds: UInt64 in [0, 1, 1_787_680_800_000, 1_787_680_800_999] {
      #expect(
        UsageTimestamp(unixMilliseconds: milliseconds).date
          == Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
      )
    }
  }
}
