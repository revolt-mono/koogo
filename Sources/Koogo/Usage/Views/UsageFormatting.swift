import Foundation

extension UsagePeriod {
    var title: String {
        switch self {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }
}

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    static var usd: Self {
        .currency(code: "USD")
            .locale(.display)
            .precision(.fractionLength(2))
            .rounded(rule: .toNearestOrAwayFromZero)
    }
}

extension FormatStyle where Self == IntegerFormatStyle<UInt64> {
    static var compactTokens: Self {
        .number
            .locale(.display)
            .notation(.compactName)
            .precision(.fractionLength(0...1))
    }
}

extension FormatStyle where Self == Decimal.FormatStyle.Percent {
    static var usagePercent: Self {
        .percent
            .locale(.display)
            .precision(.fractionLength(0...1))
            .rounded(rule: .toNearestOrAwayFromZero)
    }
}
