import Foundation

struct CodexTokenUsage: Equatable, Sendable {
    let input: UInt64
    let cachedInput: UInt64
    let cacheWrite: UInt64
    let output: UInt64
    let reasoningOutput: UInt64
    let processed: UInt64

    init?(
        input: UInt64,
        cachedInput: UInt64,
        cacheWrite: UInt64,
        output: UInt64,
        reasoningOutput: UInt64,
        processed: UInt64
    ) {
        let (cachedAndWritten, overflow) = cachedInput.addingReportingOverflow(cacheWrite)
        guard !overflow, cachedAndWritten <= input, reasoningOutput <= output else {
            return nil
        }
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
        self.reasoningOutput = reasoningOutput
        self.processed = processed
    }

    var uncachedInput: UInt64 {
        input - cachedInput - cacheWrite
    }
}

enum CodexUsagePricing {
    private static let longContextThreshold: UInt64 = 272_000

    /// Nanodollars per token (USD per million tokens × 1_000).
    private struct Rates: Sendable {
        let input: Decimal
        let cachedInput: Decimal
        let output: Decimal
        let supportsCacheWrite: Bool

        var longContext: Rates {
            Rates(
                input: input * 2,
                cachedInput: cachedInput * 2,
                output: output * 3 / 2,
                supportsCacheWrite: supportsCacheWrite
            )
        }

        func costNanodollars(for tokens: CodexTokenUsage) -> Decimal? {
            guard supportsCacheWrite || tokens.cacheWrite == 0 else {
                return nil
            }
            return Decimal(tokens.uncachedInput) * input
                + Decimal(tokens.cachedInput) * cachedInput
                + Decimal(tokens.cacheWrite) * (input * 5 / 4)
                + Decimal(tokens.output) * output
        }
    }

    private enum ContextRates: Sendable {
        case flat(Rates)
        /// The whole request bills at long-context rates once its input passes the threshold.
        case tiered(Rates)

        func costNanodollars(for tokens: CodexTokenUsage) -> Decimal? {
            switch self {
            case .flat(let rates):
                rates.costNanodollars(for: tokens)
            case .tiered(let rates):
                (tokens.input > longContextThreshold ? rates.longContext : rates).costNanodollars(for: tokens)
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

    static func quote(model: String, tokens: CodexTokenUsage) -> UsageQuote? {
        let modelID =
            model == "gpt-5.6"
            ? "gpt-5.6-sol"
            : model
        guard
            let price = prices[modelID],
            let costNanodollars = price.rates.costNanodollars(for: tokens)
        else {
            return nil
        }

        // Codex rollout logs do not reliably record service tiers, so usage uses standard rates.
        return UsageQuote(
            model: .named(id: modelID, name: price.displayName),
            costUSD: costNanodollars / 1_000_000_000
        )
    }
}
