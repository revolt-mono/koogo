import Foundation

enum ClaudeUsagePricing {
    private struct Rates: Sendable {
        let input: Decimal
        let cacheRead: Decimal
        let cacheWriteFiveMinute: Decimal
        let cacheWriteOneHour: Decimal
        let output: Decimal

        func cost(for tokens: UsageEvent.Claude.Tokens) -> Decimal {
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
            displayName: "Claude Fable 5",
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
            displayName: "Claude Mythos 5",
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
            displayName: "Claude Opus 5",
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
            displayName: "Claude Opus 4.8",
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
            displayName: "Claude Opus 4.7",
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
            displayName: "Claude Opus 4.6",
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
            displayName: "Claude Opus 4.5",
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
            displayName: "Claude Sonnet 5",
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
            displayName: "Claude Sonnet 4.6",
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
            displayName: "Claude Sonnet 4.5",
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
            displayName: "Claude Haiku 4.5",
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

    static func quote(for event: UsageEvent.Claude) -> UsageQuote? {
        let modelID =
            switch event.details.model {
            case "claude-opus-4-5": "claude-opus-4-5-20251101"
            case "claude-sonnet-4-5": "claude-sonnet-4-5-20250929"
            case "claude-haiku-4-5": "claude-haiku-4-5-20251001"
            default: event.details.model
            }
        guard let price = prices[modelID] else {
            return nil
        }
        let rates =
            switch event.speed {
            case .implicitStandard, .standard: Optional(price.standard)
            case .fast: price.fast
            }
        guard let rates else {
            return nil
        }

        var cost = rates.cost(for: event.tokens)
        if event.inferenceGeo == "us" {
            guard price.supportsUSInference else {
                return nil
            }
            cost = cost * 11 / 10
        }
        return UsageQuote(
            model: UsageQuote.Model(id: modelID, displayName: price.displayName),
            costNanodollars: cost + Decimal(event.webSearchRequests) * 10_000_000
        )
    }
}
