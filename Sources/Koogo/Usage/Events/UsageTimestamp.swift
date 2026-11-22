import Foundation

/// foundation's resilient `Date` costs a call per construction, comparison, and copy on the per-line and per-event
/// paths.
struct UsageTimestamp: Comparable, Hashable, Sendable {
  init(timeIntervalSinceReferenceDate: TimeInterval) {
    self.timeIntervalSinceReferenceDate = timeIntervalSinceReferenceDate
  }

  init(_ date: Date) {
    timeIntervalSinceReferenceDate = date.timeIntervalSinceReferenceDate
  }

  init(timeIntervalSince1970: TimeInterval) {
    timeIntervalSinceReferenceDate = timeIntervalSince1970 - Self.secondsFrom1970ToReferenceDate
  }

  init(unixMilliseconds milliseconds: UInt64) {
    self.init(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
  }

  let timeIntervalSinceReferenceDate: TimeInterval

  var date: Date {
    Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate)
  }

  static func <(lhs: Self, rhs: Self) -> Bool {
    lhs.timeIntervalSinceReferenceDate < rhs.timeIntervalSinceReferenceDate
  }

  /// `Date.timeIntervalBetween1970AndReferenceDate` without its resilient accessor.
  private static let secondsFrom1970ToReferenceDate: TimeInterval = 978_307_200
}
