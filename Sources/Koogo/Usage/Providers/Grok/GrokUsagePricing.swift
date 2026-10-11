import Foundation

enum GrokUsagePricing {
    private struct ModelPrice: Sendable {
        let displayName: String
        let input: Decimal
        let cachedInput: Decimal
        let output: Decimal

        var fast: Self {
            Self(displayName: "\(displayName) Fast", input: input * 2, cachedInput: cachedInput * 2, output: output * 2)
        }
    }

    // Grok subscriptions bill one flat rate, so the standard API rates apply at any context length.
    // Sources, checked 2026-09-26:
    // https://docs.x.ai/developers/pricing
    private static let prices: [ModelID: ModelPrice] = [
        "grok-4.7": ModelPrice(displayName: "Grok 4.7", input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.6": ModelPrice(displayName: "Grok 4.6", input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.5": ModelPrice(displayName: "Grok 4.5", input: 2_000, cachedInput: 300, output: 6_000),
    ]

    static func quote(model: ModelID, tokens: GrokTokenUsage) -> UsageQuote? {
        guard let price = price(of: model) else {
            return nil
        }
        let costNanodollars =
            Decimal(tokens.uncachedInput) * price.input
            + Decimal(tokens.cachedInput) * price.cachedInput
            + Decimal(tokens.output) * price.output

        return UsageQuote(model: model, costNanodollars: costNanodollars)
    }

    static func displayName(of model: ModelID) -> String? {
        price(of: model)?.displayName
    }

    /// Grok Build logs `<model>-build` at the rates of `<model>`, and `<model>-build-fast` at twice them.
    private static func price(of model: ModelID) -> ModelPrice? {
        let name = model.rawValue
        guard let price = prices[ModelID(name.replacing(/-build(-fast)?$/, with: ""))] else {
            return nil
        }
        return name.hasSuffix("-build-fast") ? price.fast : price
    }
}
