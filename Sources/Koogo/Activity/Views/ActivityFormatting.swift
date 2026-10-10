import Foundation

enum ActivityFormatting {
    /// A number and its unit, kept apart so a headline can set them in different sizes.
    struct Measure: Equatable {
        let value: String
        let unit: String
        let text: String
    }

    private static let locale = Locale(identifier: "en_US")

    /// Binary units labelled the way activity monitor labels them: two decimals from a gigabyte up, whole megabytes below.
    static func bytes(_ bytes: UInt64) -> Measure {
        let gigabyte = Double(1 << 30)
        let megabyte = Double(1 << 20)
        let (value, unit) =
            Double(bytes) >= gigabyte
            ? (number(Double(bytes) / gigabyte, decimals: 2), "GB")
            : (number(Double(bytes) / megabyte, decimals: 0), "MB")
        return Measure(value: value, unit: unit, text: "\(value) \(unit)")
    }

    static func percent(_ fraction: Double) -> Measure {
        let value = number(fraction * 100, decimals: 0)
        return Measure(value: value, unit: "%", text: "\(value)%")
    }

    static func watts(_ watts: Double) -> Measure {
        let value = number(watts, decimals: 1)
        return Measure(value: value, unit: "W", text: "\(value) W")
    }

    /// Hours and minutes at most, whole minutes only.
    static func duration(_ duration: Duration) -> String {
        duration.formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .narrow,
                maximumUnitCount: 2,
                fractionalPart: .hide(rounded: .towardZero)
            )
            .locale(locale)
        )
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        value.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(decimals))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }
}
