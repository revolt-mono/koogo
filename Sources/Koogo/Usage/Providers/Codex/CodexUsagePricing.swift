import Foundation

enum CodexUsagePricing {
    private static let longContextThreshold: UInt64 = 272_000

    private struct Rates: Sendable {
        private(set) var input: Picodollars
        private(set) var cachedInput: Picodollars
        private(set) var output: Picodollars
        let supportsCacheWrite: Bool

        /// rates are nanodollars per token.
        init(input: UInt64, cachedInput: UInt64, output: UInt64, supportsCacheWrite: Bool) {
            self.input = Picodollars(nanodollars: input)
            self.cachedInput = Picodollars(nanodollars: cachedInput)
            self.output = Picodollars(nanodollars: output)
            self.supportsCacheWrite = supportsCacheWrite
        }

        /// models without cache-write support leave cache-writing requests unpriced.
        var cacheWrite: Picodollars? {
            supportsCacheWrite ? input.scaled(by: 5, over: 4) : nil
        }

        var longContext: Rates {
            var rates = self
            rates.input = input * 2
            rates.cachedInput = cachedInput * 2
            rates.output = output.scaled(by: 3, over: 2)
            return rates
        }

        func cost(of tokens: CodexTokenUsage) -> Picodollars? {
            guard let cacheWrite = tokens.cacheWrite == 0 ? .zero : cacheWrite else {
                return nil
            }
            return input * tokens.uncachedInput + cachedInput * tokens.cachedInput + cacheWrite * tokens.cacheWrite
                + output * tokens.output
        }
    }

    private enum ContextRates: Sendable {
        case flat(Rates)
        case tiered(Rates)

        func cost(of tokens: CodexTokenUsage) -> Picodollars? {
            switch self {
            case .flat(let rates):
                rates.cost(of: tokens)
            case .tiered(let rates):
                (tokens.input > longContextThreshold ? rates.longContext : rates).cost(of: tokens)
            }
        }
    }

    private struct ModelPrice: Sendable {
        let displayName: String
        let rates: ContextRates
    }

    // pricing checked 2026-08-26: https://developers.openai.com/api/docs/pricing and https://openai.com/index/gpt-5-6
    private static let prices: [ModelID: ModelPrice] = [
        "gpt-6.1-sol": ModelPrice(
            displayName: "GPT 6.1 Sol",
            rates: .tiered(Rates(input: 2_000, cachedInput: 100, output: 10_000, supportsCacheWrite: true))
        ),
        "gpt-6-astra": ModelPrice(
            displayName: "GPT 6 Astra",
            rates: .tiered(Rates(input: 10_000, cachedInput: 1_000, output: 50_000, supportsCacheWrite: true))
        ),
        // https://developers.openai.com/api/docs/models/gpt-6-sol
        "gpt-6-sol": ModelPrice(
            displayName: "GPT 6 Sol",
            rates: .tiered(Rates(input: 2_000, cachedInput: 200, output: 10_000, supportsCacheWrite: true))
        ),
        // https://developers.openai.com/api/docs/models/gpt-6-luna
        "gpt-6-luna": ModelPrice(
            displayName: "GPT 6 Luna",
            rates: .tiered(Rates(input: 100, cachedInput: 10, output: 500, supportsCacheWrite: true))
        ),
        "gpt-daybreak-blue-latest": ModelPrice(
            displayName: "Daybreak Blue",
            rates: .tiered(Rates(input: 5_000, cachedInput: 500, output: 30_000, supportsCacheWrite: true))
        ),
        "gpt-5.6-sol": ModelPrice(
            displayName: "GPT 5.6 Sol",
            rates: .tiered(Rates(input: 5_000, cachedInput: 500, output: 30_000, supportsCacheWrite: true))
        ),
        "gpt-5.6-terra": ModelPrice(
            displayName: "GPT 5.6 Terra",
            rates: .tiered(Rates(input: 2_000, cachedInput: 200, output: 12_000, supportsCacheWrite: true))
        ),
        "gpt-5.6-luna": ModelPrice(
            displayName: "GPT 5.6 Luna",
            rates: .tiered(Rates(input: 200, cachedInput: 20, output: 1_200, supportsCacheWrite: true))
        ),
        "gpt-5.5": ModelPrice(
            displayName: "GPT 5.5",
            rates: .tiered(Rates(input: 5_000, cachedInput: 500, output: 30_000, supportsCacheWrite: false))
        ),
        "gpt-5.4": ModelPrice(
            displayName: "GPT 5.4",
            rates: .tiered(Rates(input: 2_500, cachedInput: 250, output: 15_000, supportsCacheWrite: false))
        ),
        "gpt-5.4-mini": ModelPrice(
            displayName: "GPT 5.4 Mini",
            rates: .flat(Rates(input: 750, cachedInput: 75, output: 4_500, supportsCacheWrite: false))
        ),
        "gpt-5.3-codex": ModelPrice(
            displayName: "GPT 5.3 Codex",
            rates: .flat(Rates(input: 1_750, cachedInput: 175, output: 14_000, supportsCacheWrite: false))
        ),
    ]

    static func quote(model: ModelID, tokens: CodexTokenUsage) -> UsageQuote? {
        guard let index = prices.index(forKey: model == "gpt-5.6" ? "gpt-5.6-sol" : model) else {
            return nil
        }
        let (model, price) = prices[index]
        guard let cost = price.rates.cost(of: tokens) else {
            return nil
        }

        // codex rollout logs lack reliable service tiers; estimates use standard rates.
        return UsageQuote(model: model, cost: cost)
    }

    static func displayName(of model: ModelID) -> String? {
        prices[model]?.displayName
    }
}
