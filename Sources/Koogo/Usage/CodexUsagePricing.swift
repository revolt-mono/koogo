import Foundation

enum CodexUsagePricing {
    private enum CacheWriteRate: Sendable {
        case unsupported
        case priced(Decimal)
    }

    private struct Rates: Sendable {
        let input: Decimal
        let cachedInput: Decimal
        let cacheWrite: CacheWriteRate
        let output: Decimal

        func cost(for tokens: UsageEvent.Codex.Tokens) -> Decimal? {
            let cacheWriteCost: Decimal
            switch (cacheWrite, tokens.cacheWrite) {
            case (.unsupported, 0):
                cacheWriteCost = 0
            case (.unsupported, _):
                return nil
            case (.priced(let rate), let amount):
                cacheWriteCost = Decimal(amount) * rate
            }
            return Decimal(tokens.uncachedInput) * input
                + Decimal(tokens.cachedInput) * cachedInput
                + cacheWriteCost
                + Decimal(tokens.output) * output
        }
    }

    private enum ContextRates: Sendable {
        case flat(Rates)
        case tiered(short: Rates, long: Rates)

        func cost(for tokens: UsageEvent.Codex.Tokens) -> Decimal? {
            switch self {
            case .flat(let rates):
                rates.cost(for: tokens)
            case .tiered(let short, let long):
                (tokens.input > 272_000 ? long : short).cost(for: tokens)
            }
        }
    }

    private struct ModelPrice: Sendable {
        let displayName: String
        let rates: ContextRates
    }

    // Sources, checked 2026-08-26:
    // https://developers.openai.com/api/docs/pricing
    // https://openai.com/index/gpt-5-6
    private static let prices: [String: ModelPrice] = [
        "gpt-daybreak-blue-latest": ModelPrice(
            displayName: "Daybreak Blue",
            rates: .tiered(
                short: Rates(
                    input: 5_000,
                    cachedInput: 500,
                    cacheWrite: .priced(6_250),
                    output: 30_000
                ),
                long: Rates(
                    input: 10_000,
                    cachedInput: 1_000,
                    cacheWrite: .priced(12_500),
                    output: 45_000
                )
            )
        ),
        "gpt-5.6-sol": ModelPrice(
            displayName: "GPT 5.6 Sol",
            rates: .tiered(
                short: Rates(
                    input: 5_000,
                    cachedInput: 500,
                    cacheWrite: .priced(6_250),
                    output: 30_000
                ),
                long: Rates(
                    input: 10_000,
                    cachedInput: 1_000,
                    cacheWrite: .priced(12_500),
                    output: 45_000
                )
            )
        ),
        "gpt-5.6-terra": ModelPrice(
            displayName: "GPT 5.6 Terra",
            rates: .tiered(
                short: Rates(
                    input: 2_000,
                    cachedInput: 200,
                    cacheWrite: .priced(2_500),
                    output: 12_000
                ),
                long: Rates(
                    input: 4_000,
                    cachedInput: 400,
                    cacheWrite: .priced(5_000),
                    output: 18_000
                )
            )
        ),
        "gpt-5.6-luna": ModelPrice(
            displayName: "GPT 5.6 Luna",
            rates: .tiered(
                short: Rates(
                    input: 200,
                    cachedInput: 20,
                    cacheWrite: .priced(250),
                    output: 1_200
                ),
                long: Rates(
                    input: 400,
                    cachedInput: 40,
                    cacheWrite: .priced(500),
                    output: 1_800
                )
            )
        ),
        "gpt-5.5": ModelPrice(
            displayName: "GPT 5.5",
            rates: .tiered(
                short: Rates(
                    input: 5_000,
                    cachedInput: 500,
                    cacheWrite: .unsupported,
                    output: 30_000
                ),
                long: Rates(
                    input: 10_000,
                    cachedInput: 1_000,
                    cacheWrite: .unsupported,
                    output: 45_000
                )
            )
        ),
        "gpt-5.4": ModelPrice(
            displayName: "GPT 5.4",
            rates: .tiered(
                short: Rates(
                    input: 2_500,
                    cachedInput: 250,
                    cacheWrite: .unsupported,
                    output: 15_000
                ),
                long: Rates(
                    input: 5_000,
                    cachedInput: 500,
                    cacheWrite: .unsupported,
                    output: 22_500
                )
            )
        ),
        "gpt-5.4-mini": ModelPrice(
            displayName: "GPT 5.4 Mini",
            rates: .flat(
                Rates(
                    input: 750,
                    cachedInput: 75,
                    cacheWrite: .unsupported,
                    output: 4_500
                )
            )
        ),
        "gpt-5.3-codex": ModelPrice(
            displayName: "GPT 5.3 Codex",
            rates: .flat(
                Rates(
                    input: 1_750,
                    cachedInput: 175,
                    cacheWrite: .unsupported,
                    output: 14_000
                )
            )
        ),
    ]

    static func quote(for event: UsageEvent.Codex) -> UsagePricing.Quote? {
        let modelID = event.details.model == "gpt-5.6"
            ? "gpt-5.6-sol"
            : event.details.model
        guard
            let price = prices[modelID],
            let cost = price.rates.cost(for: event.tokens)
        else {
            return nil
        }

        // Codex rollout logs do not reliably record service tiers, so usage uses standard rates.
        return UsagePricing.Quote(
            model: UsagePricing.Model(id: modelID, displayName: price.displayName),
            costNanodollars: cost
        )
    }
}
