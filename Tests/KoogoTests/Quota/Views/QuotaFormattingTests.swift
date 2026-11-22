import Foundation
import Testing

@testable import Koogo

struct QuotaFormattingTests {
  @Test
  func `time remaining includes the next smaller unit`() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let cases: [(TimeInterval, String)] = [
      (2 * 86_400 + 6 * 3_600 + 59 * 60, "in 2d 6h"),
      (60, "in 1m"),
      (59, "soon"),
      (-1, "soon"),
    ]

    for (interval, expected) in cases {
      #expect(now.addingTimeInterval(interval).formatted(.timeRemaining(from: now)) == expected)
    }
  }
}
