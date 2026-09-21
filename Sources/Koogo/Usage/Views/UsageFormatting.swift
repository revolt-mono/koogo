import Foundation

enum UsageFormatting {
    private static let locale = Locale(identifier: "en_US")

    static func cost(_ cost: Decimal) -> String {
        cost.formatted(
            .currency(code: "USD")
                .locale(locale)
                .precision(.fractionLength(2))
                .rounded(rule: .toNearestOrAwayFromZero)
        )
    }

    static func tokens(_ tokens: Decimal) -> String {
        tokens.formatted(
            .number
                .locale(locale)
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    static func percentage(_ fraction: Decimal) -> String {
        (fraction * 100).formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(0...1))
                .rounded(rule: .toNearestOrAwayFromZero)
        ) + "%"
    }
}
