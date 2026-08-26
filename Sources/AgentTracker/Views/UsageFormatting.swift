import Foundation

enum UsageFormatting {
    private static let locale = Locale(identifier: "en_US")

    static func cost(_ cost: Decimal) -> String {
        var cost = cost
        var roundedCost = Decimal()
        NSDecimalRound(&roundedCost, &cost, 2, .plain)
        return roundedCost.formatted(
            .currency(code: "USD")
                .locale(locale)
                .precision(.fractionLength(2))
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
}
