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
            Double(bytes) >= gigabyte
            ? ((Double(bytes) / gigabyte).formatted(.activityNumber(decimals: 2)), "GB")
            : ((Double(bytes) / megabyte).formatted(.activityNumber(decimals: 0)), "MB")
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

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    fileprivate static func activityNumber(decimals: Int) -> Self {
        .number
            .locale(.display)
            .precision(.fractionLength(decimals))
            .rounded(rule: .toNearestOrAwayFromZero)
    }
}
