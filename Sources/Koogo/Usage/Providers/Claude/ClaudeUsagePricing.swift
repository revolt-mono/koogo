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

enum ClaudeUsageSpeed: Sendable {
    case implicitStandard
    case standard
    case fast
}

struct ClaudeBillableUsage: Sendable {
    let tokens: ClaudeTokenUsage
    let speed: ClaudeUsageSpeed
    let inferenceGeo: String?
    let webSearchRequests: UInt64

    func metadataCompleteness(reasoningEffort: String?) -> Int {
        let explicitSpeed =
            switch speed {
            case .implicitStandard: 0
            case .standard, .fast: 1
            }
        let explicitCacheDuration =
            switch tokens.cacheCreation {
            case .aggregate: 0
            case .byDuration: 1
            }
        return explicitSpeed
            + explicitCacheDuration
            + (reasoningEffort == nil ? 0 : 1)
    }
}

enum ClaudeUsagePricing {
    private struct Rates: Sendable {
        let input: Decimal
        let cacheRead: Decimal
        let cacheWriteFiveMinute: Decimal
        let cacheWriteOneHour: Decimal
        let output: Decimal

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
        let standard: Rates
        let fast: Rates?
        let supportsUSInference: Bool
    }

    // Sources, checked 2026-08-26:
    // https://platform.claude.com/docs/en/about-claude/pricing
    // https://platform.claude.com/docs/en/models/overview
    private static let prices: [String: ModelPrice] = [
        "claude-fable-5": ModelPrice(
            displayName: "Fable 5",
            standard: Rates(
                input: 10_000,
                cacheRead: 1_000,
                cacheWriteFiveMinute: 12_500,
                cacheWriteOneHour: 20_000,
                output: 50_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-mythos-5": ModelPrice(
            displayName: "Mythos 5",
            standard: Rates(
                input: 10_000,
                cacheRead: 1_000,
                cacheWriteFiveMinute: 12_500,
                cacheWriteOneHour: 20_000,
                output: 50_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-5": ModelPrice(
            displayName: "Opus 5",
            standard: Rates(
                input: 5_000,
                cacheRead: 500,
                cacheWriteFiveMinute: 6_250,
                cacheWriteOneHour: 10_000,
                output: 25_000
            ),
            fast: Rates(
                input: 10_000,
                cacheRead: 1_000,
                cacheWriteFiveMinute: 12_500,
                cacheWriteOneHour: 20_000,
                output: 50_000
            ),
            supportsUSInference: true
        ),
        "claude-opus-4-8": ModelPrice(
            displayName: "Opus 4.8",
            standard: Rates(
                input: 5_000,
                cacheRead: 500,
                cacheWriteFiveMinute: 6_250,
                cacheWriteOneHour: 10_000,
                output: 25_000
            ),
            fast: Rates(
                input: 10_000,
                cacheRead: 1_000,
                cacheWriteFiveMinute: 12_500,
                cacheWriteOneHour: 20_000,
                output: 50_000
            ),
            supportsUSInference: true
        ),
        "claude-opus-4-7": ModelPrice(
            displayName: "Opus 4.7",
            standard: Rates(
                input: 5_000,
                cacheRead: 500,
                cacheWriteFiveMinute: 6_250,
                cacheWriteOneHour: 10_000,
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-4-6": ModelPrice(
            displayName: "Opus 4.6",
            standard: Rates(
                input: 5_000,
                cacheRead: 500,
                cacheWriteFiveMinute: 6_250,
                cacheWriteOneHour: 10_000,
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-4-5-20251101": ModelPrice(
            displayName: "Opus 4.5",
            standard: Rates(
                input: 5_000,
                cacheRead: 500,
                cacheWriteFiveMinute: 6_250,
                cacheWriteOneHour: 10_000,
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: false
        ),
        "claude-sonnet-5": ModelPrice(
            displayName: "Sonnet 5",
            standard: Rates(
                input: 2_000,
                cacheRead: 200,
                cacheWriteFiveMinute: 2_500,
                cacheWriteOneHour: 4_000,
                output: 10_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-sonnet-4-6": ModelPrice(
            displayName: "Sonnet 4.6",
            standard: Rates(
                input: 3_000,
                cacheRead: 300,
                cacheWriteFiveMinute: 3_750,
                cacheWriteOneHour: 6_000,
                output: 15_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-sonnet-4-5-20250929": ModelPrice(
            displayName: "Sonnet 4.5",
            standard: Rates(
                input: 3_000,
                cacheRead: 300,
                cacheWriteFiveMinute: 3_750,
                cacheWriteOneHour: 6_000,
                output: 15_000
            ),
            fast: nil,
            supportsUSInference: false
        ),
        "claude-haiku-4-5-20251001": ModelPrice(
            displayName: "Haiku 4.5",
            standard: Rates(
                input: 1_000,
                cacheRead: 100,
                cacheWriteFiveMinute: 1_250,
                cacheWriteOneHour: 2_000,
                output: 5_000
            ),
            fast: nil,
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
        let rates =
            switch usage.speed {
            case .implicitStandard, .standard: Optional(price.standard)
            case .fast: price.fast
            }
        guard let rates else {
            return nil
        }

        var costNanodollars = rates.costNanodollars(for: usage.tokens)
        if usage.inferenceGeo == "us" {
            guard price.supportsUSInference else {
                return nil
            }
            costNanodollars = costNanodollars * 11 / 10
        }
        return UsageQuote(
            model: .claude(id: modelID, name: price.displayName),
            costUSD: (costNanodollars + Decimal(usage.webSearchRequests) * 10_000_000)
                / 1_000_000_000
        )
    }
}
