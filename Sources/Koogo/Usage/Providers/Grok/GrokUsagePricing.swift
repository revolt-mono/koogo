enum GrokUsagePricing {
    private struct ModelPrice: Sendable {
        private(set) var input: Picodollars
        private(set) var cachedInput: Picodollars
        private(set) var output: Picodollars

        /// rates are nanodollars per token.
        init(input: UInt64, cachedInput: UInt64, output: UInt64) {
            self.input = Picodollars(nanodollars: input)
            self.cachedInput = Picodollars(nanodollars: cachedInput)
            self.output = Picodollars(nanodollars: output)
        }

        var fast: Self {
            var fast = self
            fast.input = input * 2
            fast.cachedInput = cachedInput * 2
            fast.output = output * 2
            return fast
        }
    }

    // grok subscriptions use standard api rates at every context length.
    // pricing checked 2026-09-26: https://docs.x.ai/developers/pricing
    private static let prices: [ModelID: ModelPrice] = [
        "grok-4.7": ModelPrice(input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.6": ModelPrice(input: 2_000, cachedInput: 500, output: 6_000),
        "grok-4.5": ModelPrice(input: 2_000, cachedInput: 300, output: 6_000),
    ]

    static func cost(of tokens: GrokTokenUsage, model: ModelID) -> Picodollars? {
        guard let price = price(of: model) else {
            return nil
        }
        return price.input * tokens.uncachedInput + price.cachedInput * tokens.cachedInput + price.output
            * tokens.output
    }

    /// grok logs build-suffixed model names.
    private static func price(of model: ModelID) -> ModelPrice? {
        let name = model.rawValue
        let suffix = ["-build-fast", "-build"].first { name.hasSuffix($0) } ?? ""
        guard let price = prices[ModelID(rawValue: String(name.dropLast(suffix.count)))] else {
            return nil
        }
        return suffix == "-build-fast" ? price.fast : price
    }
}
