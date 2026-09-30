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

    /// Held as seconds because `Date` has a resilient layout, which routes every copy of a record
    /// through runtime value witnesses.
    private let secondsSinceReferenceDate: TimeInterval
    let processedTokens: UInt64
    let costUSD: Decimal
    let modelTurn: ModelTurn?

    var timestamp: Date {
        Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
    }

    init(timestamp: Date, processedTokens: UInt64, costUSD: Decimal, modelTurn: ModelTurn?) {
        secondsSinceReferenceDate = timestamp.timeIntervalSinceReferenceDate
        self.processedTokens = processedTokens
        self.costUSD = costUSD
        self.modelTurn = modelTurn
    }
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
