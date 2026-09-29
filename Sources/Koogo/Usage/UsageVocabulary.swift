import Foundation

/// A priced model as the snapshot names it; `id` orders ties and `name` is what the UI shows.
struct UsageModelReference: Hashable, Sendable {
    let id: String
    let name: String
}

struct UsageRecord: Sendable {
    struct ModelTurn: Sendable {
        let model: UsageModelReference
        let reasoningEffort: String?
    }

    let timestamp: Date
    let processedTokens: UInt64
    let costUSD: Decimal
    let modelTurn: ModelTurn?
}

struct UsageQuote: Sendable {
    let model: UsageModelReference
    let costUSD: Decimal

    /// Takes the cost in nanodollars, the unit the pricing tables work in.
    init(model: UsageModelReference, costNanodollars: Decimal) {
        self.model = model
        // Moving the decimal point is exact and far cheaper than dividing by 10^9.
        costUSD = Decimal(
            sign: costNanodollars.sign,
            exponent: costNanodollars.exponent - 9,
            significand: costNanodollars.significand
        )
    }
}
