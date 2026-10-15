import Foundation

enum ClaudeUsagePricing {
    private static let longPromptThreshold: UInt64 = 100_000

    private struct Rates: Sendable {
        let input: Picodollars
        let cacheRead: Picodollars
        let output: Picodollars
        let cacheWriteFiveMinute: Picodollars
        let cacheWriteOneHour: Picodollars

        /// rates are nanodollars per token.
        init(input: UInt64, cacheRead: UInt64, output: UInt64) {
            self.input = Picodollars(nanodollars: input)
            self.cacheRead = Picodollars(nanodollars: cacheRead)
            self.output = Picodollars(nanodollars: output)
            cacheWriteFiveMinute = self.input.scaled(by: 5, over: 4)
            cacheWriteOneHour = self.input * 2
        }

        func cost(of tokens: ClaudeTokenUsage) -> Picodollars {
            let cacheCreationCost =
                switch tokens.cacheCreation {
                case .aggregate(let amount):
                    cacheWriteFiveMinute * amount
                case .byDuration(let fiveMinute, let oneHour):
                    cacheWriteFiveMinute * fiveMinute + cacheWriteOneHour * oneHour
                }
            return input * tokens.input + cacheRead * tokens.cacheRead + cacheCreationCost + output * tokens.output
        }
    }

    private struct ModelPrice: Sendable {
        let displayName: String
        let rates: Rates
        var longPromptRates: Rates?
        let options: Set<ClaudeBillableUsage.Option>
    }

    // pricing checked 2026-10-08: https://platform.claude.com/docs/en/about-claude/pricing and https://platform.claude.com/docs/en/models/overview
    private static let prices: [ModelID: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(
            displayName: "Fable 5.1",
            rates: Rates(input: 10_000, cacheRead: 250, output: 50_000),
            options: [.usInference]
        ),
        "claude-mythos-5-1": ModelPrice(
            displayName: "Mythos 5.1",
            rates: Rates(input: 10_000, cacheRead: 250, output: 50_000),
            options: [.usInference]
        ),
        "claude-fable-5": ModelPrice(
            displayName: "Fable 5",
            rates: Rates(input: 10_000, cacheRead: 1_000, output: 50_000),
            options: [.usInference]
        ),
        "claude-mythos-5": ModelPrice(
            displayName: "Mythos 5",
            rates: Rates(input: 10_000, cacheRead: 1_000, output: 50_000),
            options: [.usInference]
        ),
        "claude-opus-5-5": ModelPrice(
            displayName: "Opus 5.5",
            rates: Rates(input: 4_000, cacheRead: 200, output: 20_000),
            options: [.fastMode, .usInference]
        ),
        "claude-opus-5": ModelPrice(
            displayName: "Opus 5",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            options: [.fastMode, .usInference]
        ),
        "claude-opus-4-8": ModelPrice(
            displayName: "Opus 4.8",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            options: [.fastMode, .usInference]
        ),
        "claude-opus-4-7": ModelPrice(
            displayName: "Opus 4.7",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            options: [.usInference]
        ),
        "claude-opus-4-6": ModelPrice(
            displayName: "Opus 4.6",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            options: [.usInference]
        ),
        "claude-opus-4-5-20251101": ModelPrice(
            displayName: "Opus 4.5",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            options: []
        ),
        "claude-sonnet-5-5": ModelPrice(
            displayName: "Sonnet 5.5",
            rates: Rates(input: 2_000, cacheRead: 100, output: 10_000),
            options: [.usInference]
        ),
        "claude-sonnet-5": ModelPrice(
            displayName: "Sonnet 5",
            rates: Rates(input: 2_000, cacheRead: 200, output: 10_000),
            options: [.usInference]
        ),
        "claude-sonnet-4-6": ModelPrice(
            displayName: "Sonnet 4.6",
            rates: Rates(input: 3_000, cacheRead: 300, output: 15_000),
            options: [.usInference]
        ),
        "claude-sonnet-4-5-20250929": ModelPrice(
            displayName: "Sonnet 4.5",
            rates: Rates(input: 3_000, cacheRead: 300, output: 15_000),
            options: []
        ),
        "claude-haiku-5-5": ModelPrice(
            displayName: "Haiku 5.5",
            rates: Rates(input: 100, cacheRead: 10, output: 500),
            longPromptRates: Rates(input: 500, cacheRead: 50, output: 2_500),
            options: [.usInference]
        ),
    ]

    static func quote(model logged: ModelID, usage: ClaudeBillableUsage) -> UsageQuote? {
        let canonical: ModelID =
            switch logged {
            case "claude-opus-4-5": "claude-opus-4-5-20251101"
            case "claude-sonnet-4-5": "claude-sonnet-4-5-20250929"
            default: logged
            }
        guard let index = prices.index(forKey: canonical) else {
            return nil
        }
        let (model, price) = prices[index]

        let promptTokens = usage.tokens.processed - usage.tokens.output
        let rates = promptTokens > longPromptThreshold ? price.longPromptRates ?? price.rates : price.rates
        guard usage.options.isSubset(of: price.options) else {
            return nil
        }
        let tokenCost = usage.options.reduce(rates.cost(of: usage.tokens)) { cost, option in
            switch option {
            case .fastMode: cost * 2
            case .usInference: cost.scaled(by: 11, over: 10)
            }
        }
        return UsageQuote(
            model: model,
            cost: tokenCost + Picodollars(nanodollars: 10_000_000) * usage.webSearchRequests
        )
    }

    static func displayName(of model: ModelID) -> String? {
        prices[model]?.displayName
    }
}
