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

    private static func number(_ value: Double, decimals: Int) -> String {
        value.formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(decimals))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }
}
