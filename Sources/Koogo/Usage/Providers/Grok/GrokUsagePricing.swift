import Foundation

enum GrokUsagePricing {
    private struct ModelPrice: Sendable {
        private(set) var displayName: String
        private(set) var input: Picodollars
        private(set) var cachedInput: Picodollars
        private(set) var output: Picodollars

        /// Takes rates in nanodollars per token.
        init(displayName: String, input: UInt64, cachedInput: UInt64, output: UInt64) {
            self.displayName = displayName
            self.input = Picodollars(nanodollars: input)
            self.cachedInput = Picodollars(nanodollars: cachedInput)
            self.output = Picodollars(nanodollars: output)
        }

        var fast: Self {
            var fast = self
            fast.displayName += " Fast"
            fast.input = input * 2
            fast.cachedInput = cachedInput * 2
            fast.output = output * 2
            return fast
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

    static func cost(of tokens: GrokTokenUsage, model: ModelID) -> Picodollars? {
        guard let price = price(of: model) else {
            return nil
        }
        return price.input * tokens.uncachedInput + price.cachedInput * tokens.cachedInput + price.output
            * tokens.output
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
