import Foundation

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
        guard let (price, isFast) = price(of: model) else {
            return nil
        }
        let costNanodollars =
            Decimal(tokens.uncachedInput) * price.input
            + Decimal(tokens.cachedInput) * price.cachedInput
            + Decimal(tokens.output) * price.output

        return UsageQuote(model: ModelID(model), costNanodollars: costNanodollars * (isFast ? 2 : 1))
    }

    static func displayName(of model: ModelID) -> String? {
        price(of: model.rawValue).map { price, isFast in isFast ? "\(price.displayName) Fast" : price.displayName }
    }

    /// Grok Build logs `<model>-build` at the rates of `<model>`, and `<model>-build-fast` at twice them.
    private static func price(of model: String) -> (price: ModelPrice, isFast: Bool)? {
        prices[model.replacing(/-build(-fast)?$/, with: "")].map { ($0, model.hasSuffix("-build-fast")) }
    }
}
