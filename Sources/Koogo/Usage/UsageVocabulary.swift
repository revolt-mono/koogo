import Foundation

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

    init(model: UsageModelReference, costNanodollars: Decimal) {
        self.model = model
        costUSD = Decimal(
            sign: costNanodollars.sign,
            exponent: costNanodollars.exponent - 9,
            significand: costNanodollars.significand
        )
    }
}
