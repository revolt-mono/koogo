import Foundation

/// A cost in whole picodollars. Every priced rate, down to a tenth of a nanodollar per token, is a whole number of them, so sums stay exact integers. Arithmetic saturates instead of trapping, as token totals do. Encodes as US dollars.
struct Picodollars: Comparable, Sendable, Encodable {
    static let zero = Self(0)

    let rawValue: UInt64

    init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init(nanodollars: UInt64) {
        self = Self(1_000) * nanodollars
    }

    var usd: Decimal {
        Decimal(sign: .plus, exponent: -12, significand: Decimal(rawValue))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(usd)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(lhs.rawValue.saturatingAdding(rhs.rawValue))
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    static func * (price: Self, count: UInt64) -> Self {
        let (product, overflow) = price.rawValue.multipliedReportingOverflow(by: count)
        return Self(overflow ? .max : product)
    }

    /// Scales by a ratio such as 5/4, rounding down.
    func scaled(by numerator: UInt64, over denominator: UInt64) -> Self {
        let product = rawValue.multipliedFullWidth(by: numerator)
        guard product.high < denominator else {
            return Self(.max)
        }
        return Self(denominator.dividingFullWidth(product).quotient)
    }
}
