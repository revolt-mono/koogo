import Foundation

struct Measure {
  let value: String
  let unit: String
  let text: String
}

extension Measure {
  init(bytes: UInt64) {
    let gigabyte = Double(1 << 30)
    let megabyte = Double(1 << 20)
    let (value, unit) =
      if Double(bytes) >= gigabyte {
        ((Double(bytes) / gigabyte).formatted(.activityNumber(decimals: 2)), "GB")
      } else {
        ((Double(bytes) / megabyte).formatted(.activityNumber(decimals: 0)), "MB")
      }
    self.init(value: value, unit: unit, text: "\(value) \(unit)")
  }

  init(fraction: Double) {
    let value = (fraction * 100).formatted(.activityNumber(decimals: 0))
    self.init(value: value, unit: "%", text: "\(value)%")
  }

  init(watts: Double) {
    let value = watts.formatted(.activityNumber(decimals: 1))
    self.init(value: value, unit: "W", text: "\(value) W")
  }
}

extension CPUCores {
  var summary: String {
    switch self {
    case .uniform(let count): "\(count) cores"
    case .hybrid(let performance, let efficiency): "\(performance)P · \(efficiency)E"
    }
  }
}

extension BatteryState.Supply {
  var summary: String {
    switch self {
    case .charging(let timeToFull?): "charging · \(timeToFull.formatted(.batteryEstimate)) to full"
    case .charging(nil): "charging"
    case .external: "on power"
    case .discharging(let timeToEmpty?): "\(timeToEmpty.formatted(.batteryEstimate)) left"
    case .discharging(nil): "on battery"
    }
  }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
  fileprivate static func activityNumber(decimals: Int) -> Self {
    .number
      .locale(.display)
      .precision(.fractionLength(decimals))
      .rounded(rule: .toNearestOrAwayFromZero)
  }
}

extension FormatStyle where Self == Duration.UnitsFormatStyle {
  fileprivate static var batteryEstimate: Self {
    .displayUnits(allowed: [.hours, .minutes])
  }
}
