import Foundation

struct ClaudeTokenUsage: Sendable {
    enum CacheCreation: Sendable {
        case aggregate(UInt64)
        case byDuration(fiveMinute: UInt64, oneHour: UInt64)
    }

    let input: UInt64
    let cacheRead: UInt64
    let cacheCreation: CacheCreation
    let output: UInt64
    let processed: UInt64

    init?(
        input: UInt64,
        cacheRead: UInt64,
        cacheCreation: CacheCreation,
        output: UInt64
    ) {
        var processed = UInt64.zero
        let amounts =
            switch cacheCreation {
            case .aggregate(let tokens): [input, cacheRead, tokens, output]
            case .byDuration(let fiveMinute, let oneHour):
                [input, cacheRead, fiveMinute, oneHour, output]
            }
        for amount in amounts {
            let (sum, overflow) = processed.addingReportingOverflow(amount)
            guard !overflow else {
                return nil
            }
            processed = sum
        }
        self.input = input
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
        self.output = output
        self.processed = processed
    }
}

struct ClaudeBillableUsage: Sendable {
    let tokens: ClaudeTokenUsage
    let isFast: Bool
    let isUSInference: Bool
    let webSearchRequests: UInt64
}

enum ClaudeUsagePricing {
    /// Nanodollars per token (USD per million tokens × 1_000).
    private struct Rates: Sendable {
        let input: Decimal
        let cacheRead: Decimal
        let output: Decimal
        let cacheWriteFiveMinute: Decimal
        let cacheWriteOneHour: Decimal

        init(input: Decimal, cacheRead: Decimal, output: Decimal) {
            self.input = input
            self.cacheRead = cacheRead
            self.output = output
            cacheWriteFiveMinute = input * 5 / 4
            cacheWriteOneHour = input * 2
        }

        func costNanodollars(for tokens: ClaudeTokenUsage) -> Decimal {
            let cacheCreationCost =
                switch tokens.cacheCreation {
                case .aggregate(let amount):
                    Decimal(amount) * cacheWriteFiveMinute
                case .byDuration(let fiveMinute, let oneHour):
                    Decimal(fiveMinute) * cacheWriteFiveMinute
                        + Decimal(oneHour) * cacheWriteOneHour
                }
            return Decimal(tokens.input) * input
                + Decimal(tokens.cacheRead) * cacheRead
                + cacheCreationCost
                + Decimal(tokens.output) * output
        }
    }

    private struct ModelPrice: Sendable {
        let displayName: String
        let rates: Rates
        let supportsFastMode: Bool
        let supportsUSInference: Bool
    }

    // Sources, checked 2026-09-23:
    // https://platform.claude.com/docs/en/about-claude/pricing
    // https://platform.claude.com/docs/en/models/overview
    private static let prices: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(
            displayName: "Fable 5.1",
            rates: Rates(input: 10_000, cacheRead: 250, output: 50_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-mythos-5-1": ModelPrice(
            displayName: "Mythos 5.1",
            rates: Rates(input: 10_000, cacheRead: 250, output: 50_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-fable-5": ModelPrice(
            displayName: "Fable 5",
            rates: Rates(input: 10_000, cacheRead: 1_000, output: 50_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-mythos-5": ModelPrice(
            displayName: "Mythos 5",
            rates: Rates(input: 10_000, cacheRead: 1_000, output: 50_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-opus-5-5": ModelPrice(
            displayName: "Opus 5.5",
            rates: Rates(input: 4_000, cacheRead: 200, output: 20_000),
            supportsFastMode: true,
            supportsUSInference: true
        ),
        "claude-opus-5": ModelPrice(
            displayName: "Opus 5",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            supportsFastMode: true,
            supportsUSInference: true
        ),
        "claude-opus-4-8": ModelPrice(
            displayName: "Opus 4.8",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            supportsFastMode: true,
            supportsUSInference: true
        ),
        "claude-opus-4-7": ModelPrice(
            displayName: "Opus 4.7",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-opus-4-6": ModelPrice(
            displayName: "Opus 4.6",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-opus-4-5-20251101": ModelPrice(
            displayName: "Opus 4.5",
            rates: Rates(input: 5_000, cacheRead: 500, output: 25_000),
            supportsFastMode: false,
            supportsUSInference: false
        ),
        "claude-sonnet-5": ModelPrice(
            displayName: "Sonnet 5",
            rates: Rates(input: 2_000, cacheRead: 200, output: 10_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-sonnet-4-6": ModelPrice(
            displayName: "Sonnet 4.6",
            rates: Rates(input: 3_000, cacheRead: 300, output: 15_000),
            supportsFastMode: false,
            supportsUSInference: true
        ),
        "claude-sonnet-4-5-20250929": ModelPrice(
            displayName: "Sonnet 4.5",
            rates: Rates(input: 3_000, cacheRead: 300, output: 15_000),
            supportsFastMode: false,
            supportsUSInference: false
        ),
        "claude-haiku-4-5-20251001": ModelPrice(
            displayName: "Haiku 4.5",
            rates: Rates(input: 1_000, cacheRead: 100, output: 5_000),
            supportsFastMode: false,
            supportsUSInference: false
        ),
    ]

    static func quote(model: String, usage: ClaudeBillableUsage) -> UsageQuote? {
        let modelID =
            switch model {
            case "claude-opus-4-5": "claude-opus-4-5-20251101"
            case "claude-sonnet-4-5": "claude-sonnet-4-5-20250929"
            case "claude-haiku-4-5": "claude-haiku-4-5-20251001"
            default: model
            }
        guard let price = prices[modelID] else {
            return nil
        }

        var costNanodollars = price.rates.costNanodollars(for: usage.tokens)
        if usage.isFast {
            guard price.supportsFastMode else {
                return nil
            }
            // Fast mode doubles the standard cost.
            costNanodollars *= 2
        }
        if usage.isUSInference {
            guard price.supportsUSInference else {
                return nil
            }
            costNanodollars = costNanodollars * 11 / 10
        }
        return UsageQuote(
            model: .named(id: modelID, name: price.displayName),
            costNanodollars: costNanodollars + Decimal(usage.webSearchRequests) * 10_000_000
        )
    }
}
