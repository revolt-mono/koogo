import Foundation

/// One model's share of a Grok turn.
struct GrokTokenUsage: Sendable {
    /// Full prompt input, cache reads included.
    let input: UInt64
    let cachedInput: UInt64
    let output: UInt64
    let modelCalls: UInt64

    init?(input: UInt64, cachedInput: UInt64, output: UInt64, modelCalls: UInt64) {
        guard cachedInput <= input else {
            return nil
        }
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.modelCalls = modelCalls
    }

    var uncachedInput: UInt64 {
        input - cachedInput
    }
}

enum GrokUsagePricing {
    private struct ModelPrice: Sendable {
        let displayName: String
        let input: Decimal
        let cachedInput: Decimal
        let output: Decimal
    }

    // Grok subscriptions bill one flat rate, so the standard API rates apply at any context length.
    // Sources, checked 2026-09-26:
    // https://docs.x.ai/developers/pricing
    private static let prices: [String: ModelPrice] = [
        "grok-4.7": ModelPrice(displayName: "Grok 4.7", input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.6": ModelPrice(displayName: "Grok 4.6", input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.5": ModelPrice(displayName: "Grok 4.5", input: 2_000, cachedInput: 300, output: 6_000),
    ]

    static func quote(model: String, tokens: GrokTokenUsage) -> UsageQuote? {
        // Grok Build logs `<model>-build` at the rates of `<model>`, and `<model>-build-fast` at twice them.
        let isFast = model.hasSuffix("-build-fast")
        guard let price = prices[model.replacing(/-build(-fast)?$/, with: "")] else {
            return nil
        }
        let costNanodollars =
            Decimal(tokens.uncachedInput) * price.input
            + Decimal(tokens.cachedInput) * price.cachedInput
            + Decimal(tokens.output) * price.output

        return UsageQuote(
            model: .named(id: model, name: isFast ? "\(price.displayName) Fast" : price.displayName),
            costNanodollars: costNanodollars * (isFast ? 2 : 1)
        )
    }
}
