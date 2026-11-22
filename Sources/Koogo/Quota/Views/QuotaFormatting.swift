import Foundation

struct TimeRemainingFormatStyle: FormatStyle {
  let now: Date

  func format(_ deadline: Date) -> String {
    let remaining = Duration.seconds(deadline.timeIntervalSince(now))
    guard remaining >= .seconds(60) else {
      return "soon"
    }
    return "in \(remaining.formatted(.displayUnits(allowed: [.days, .hours, .minutes])))"
  }
}

extension FormatStyle where Self == TimeRemainingFormatStyle {
  static func timeRemaining(from now: Date) -> Self {
    TimeRemainingFormatStyle(now: now)
  }
}
