import Foundation

struct UsagePriceCatalog: Sendable {
    // Sources, checked 2026-08-26:
    // https://developers.openai.com/api/docs/pricing
    // https://openai.com/index/gpt-5-6
    // https://platform.claude.com/docs/en/about-claude/pricing
    // https://platform.claude.com/docs/en/models/overview
    static let pricingAsOf = "2026-08-26"

    struct Model: Hashable, Sendable {
        fileprivate let id: String
        let displayName: String
    }

    struct Quote: Sendable {
        let model: Model
        let costNanodollars: Decimal
    }

    private struct Rates: Sendable {
        let input: Decimal
        let cachedInput: Decimal
        let cacheWrite5MinuteInput: Decimal?
        let cacheWrite1HourInput: Decimal?
        let output: Decimal

        init(
            _ input: Decimal,
            _ cachedInput: Decimal,
            _ cacheWrite5MinuteInput: Decimal?,
            _ output: Decimal
        ) {
            self.input = input
            self.cachedInput = cachedInput
            self.cacheWrite5MinuteInput = cacheWrite5MinuteInput
            cacheWrite1HourInput = nil
            self.output = output
        }

        init(
            _ input: Decimal,
            _ cachedInput: Decimal,
            _ cacheWrite5MinuteInput: Decimal,
            _ cacheWrite1HourInput: Decimal,
            _ output: Decimal
        ) {
            self.input = input
            self.cachedInput = cachedInput
            self.cacheWrite5MinuteInput = cacheWrite5MinuteInput
            self.cacheWrite1HourInput = cacheWrite1HourInput
            self.output = output
        }

        func cost(for tokens: UsageTokens) -> Decimal? {
            guard
                let cacheWrite5MinuteCost = cost(
                    tokens.cacheWrite5MinuteInput,
                    at: cacheWrite5MinuteInput
                ),
                let cacheWrite1HourCost = cost(
                    tokens.cacheWrite1HourInput,
                    at: cacheWrite1HourInput
                )
            else {
                return nil
            }

            return Decimal(tokens.uncachedInput) * input
                + Decimal(tokens.cachedInput) * cachedInput
                + cacheWrite5MinuteCost
                + cacheWrite1HourCost
                + Decimal(tokens.output) * output
        }

        private func cost(_ tokens: Int64, at rate: Decimal?) -> Decimal? {
            tokens == 0 ? 0 : rate.map { Decimal(tokens) * $0 }
        }
    }

    private enum ContextRates: Sendable {
        case flat(Rates)
        case tiered(short: Rates, long: Rates)

        func resolved(forInputTokens inputTokens: Int64) -> Rates {
            switch self {
            case .flat(let rates):
                rates
            case .tiered(let short, let long):
                inputTokens > 272_000 ? long : short
            }
        }
    }

    private struct CodexModelPrice: Sendable {
        let displayName: String
        let rates: ContextRates
    }

    private struct ClaudeModelPrice: Sendable {
        let displayName: String
        let standard: Rates
        let fast: Rates?
        let supportsUSInference: Bool

        init(
            _ displayName: String,
            _ standard: Rates,
            fast: Rates? = nil,
            supportsUSInference: Bool = true
        ) {
            self.displayName = displayName
            self.standard = standard
            self.fast = fast
            self.supportsUSInference = supportsUSInference
        }
    }

    private static let codexPrices: [String: CodexModelPrice] = [
        "gpt-5.6-sol": CodexModelPrice(
            displayName: "GPT 5.6 Sol",
            rates: .tiered(
                short: Rates(5_000, 500, 6_250, 30_000),
                long: Rates(10_000, 1_000, 12_500, 45_000)
            )
        ),
        "gpt-5.6-terra": CodexModelPrice(
            displayName: "GPT 5.6 Terra",
            rates: .tiered(
                short: Rates(2_000, 200, 2_500, 12_000),
                long: Rates(4_000, 400, 5_000, 18_000)
            )
        ),
        "gpt-5.6-luna": CodexModelPrice(
            displayName: "GPT 5.6 Luna",
            rates: .tiered(
                short: Rates(200, 20, 250, 1_200),
                long: Rates(400, 40, 500, 1_800)
            )
        ),
        "gpt-5.5": CodexModelPrice(
            displayName: "GPT 5.5",
            rates: .tiered(
                short: Rates(5_000, 500, nil, 30_000),
                long: Rates(10_000, 1_000, nil, 45_000)
            )
        ),
        "gpt-5.4": CodexModelPrice(
            displayName: "GPT 5.4",
            rates: .tiered(
                short: Rates(2_500, 250, nil, 15_000),
                long: Rates(5_000, 500, nil, 22_500)
            )
        ),
        "gpt-5.4-mini": CodexModelPrice(
            displayName: "GPT 5.4 Mini",
            rates: .flat(Rates(750, 75, nil, 4_500))
        ),
        "gpt-5.3-codex": CodexModelPrice(
            displayName: "GPT 5.3 Codex",
            rates: .flat(Rates(1_750, 175, nil, 14_000))
        ),
    ]

    private static let codexAliases: [String: String] = [
        "gpt-5.6": "gpt-5.6-sol",
        "gpt-daybreak-blue-latest": "gpt-5.6-sol",
        "daybreak-blue-latest": "gpt-5.6-sol",
    ]

    private static let claudePrices: [String: ClaudeModelPrice] = [
        "claude-fable-5": ClaudeModelPrice(
            "Claude Fable 5",
            Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-mythos-5": ClaudeModelPrice(
            "Claude Mythos 5",
            Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-opus-5": ClaudeModelPrice(
            "Claude Opus 5",
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            fast: Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-opus-4-8": ClaudeModelPrice(
            "Claude Opus 4.8",
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            fast: Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-opus-4-7": ClaudeModelPrice(
            "Claude Opus 4.7",
            Rates(5_000, 500, 6_250, 10_000, 25_000)
        ),
        "claude-opus-4-6": ClaudeModelPrice(
            "Claude Opus 4.6",
            Rates(5_000, 500, 6_250, 10_000, 25_000)
        ),
        "claude-opus-4-5-20251101": ClaudeModelPrice(
            "Claude Opus 4.5",
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            supportsUSInference: false
        ),
        "claude-sonnet-5": ClaudeModelPrice(
            "Claude Sonnet 5",
            Rates(2_000, 200, 2_500, 4_000, 10_000)
        ),
        "claude-sonnet-4-6": ClaudeModelPrice(
            "Claude Sonnet 4.6",
            Rates(3_000, 300, 3_750, 6_000, 15_000)
        ),
        "claude-sonnet-4-5-20250929": ClaudeModelPrice(
            "Claude Sonnet 4.5",
            Rates(3_000, 300, 3_750, 6_000, 15_000),
            supportsUSInference: false
        ),
        "claude-haiku-4-5-20251001": ClaudeModelPrice(
            "Claude Haiku 4.5",
            Rates(1_000, 100, 1_250, 2_000, 5_000),
            supportsUSInference: false
        ),
    ]

    private static let claudeAliases: [String: String] = [
        "claude-opus-4-5": "claude-opus-4-5-20251101",
        "claude-sonnet-4-5": "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5": "claude-haiku-4-5-20251001",
    ]

    func quote(for event: UsageEvent) -> Quote? {
        switch event {
        case .codex(let event):
            codexQuote(event)
        case .claude(let event):
            claudeQuote(event)
        }
    }

    private func codexQuote(_ event: UsageEvent.Codex) -> Quote? {
        let modelID = Self.codexAliases[event.details.model] ?? event.details.model
        guard let price = Self.codexPrices[modelID] else {
            return nil
        }

        // Codex rollout logs do not reliably record service tiers, so usage always uses standard rates.
        let tokens = event.details.tokens
        let inputTokens = tokens.uncachedInput
            + tokens.cachedInput
            + tokens.cacheWrite5MinuteInput
        guard let cost = price.rates.resolved(forInputTokens: inputTokens).cost(for: tokens) else {
            return nil
        }
        return Quote(
            model: Model(id: modelID, displayName: price.displayName),
            costNanodollars: cost
        )
    }

    private func claudeQuote(_ event: UsageEvent.Claude) -> Quote? {
        let modelID = Self.claudeAliases[event.details.model] ?? event.details.model
        guard let price = Self.claudePrices[modelID] else {
            return nil
        }

        let rates: Rates?
        switch event.speed {
        case .standard: rates = price.standard
        case .fast: rates = price.fast
        }
        guard var cost = rates?.cost(for: event.details.tokens) else {
            return nil
        }

        if event.inferenceGeo == "us" {
            guard price.supportsUSInference else {
                return nil
            }
            cost = cost * 11 / 10
        }

        return Quote(
            model: Model(id: modelID, displayName: price.displayName),
            costNanodollars: cost + Decimal(event.webSearchRequests) * 10_000_000
        )
    }
}

struct UsageSnapshotBuilder {
    private struct ModelUsage {
        var occurrences = 0
        var reasoningEfforts: [String: Int] = [:]

        mutating func add(reasoningEffort: String?) {
            occurrences += 1
            if let reasoningEffort {
                reasoningEfforts[reasoningEffort, default: 0] += 1
            }
        }

        mutating func merge(_ other: ModelUsage) {
            occurrences += other.occurrences
            reasoningEfforts.merge(other.reasoningEfforts, uniquingKeysWith: +)
        }
    }

    private struct Accumulator {
        var processedTokens: Decimal = 0
        var costNanodollars: Decimal = 0
        var models: [UsagePriceCatalog.Model: ModelUsage] = [:]

        mutating func add(
            _ details: UsageEvent.Details,
            quote: UsagePriceCatalog.Quote
        ) {
            processedTokens += Decimal(details.tokens.processed)
            costNanodollars += quote.costNanodollars
            models[quote.model, default: ModelUsage()].add(
                reasoningEffort: details.reasoningEffort
            )
        }

        mutating func merge(_ other: Accumulator) {
            processedTokens += other.processedTokens
            costNanodollars += other.costNanodollars
            for (model, usage) in other.models {
                models[model, default: ModelUsage()].merge(usage)
            }
        }

        var favorite: ProviderUsageSnapshot.Favorite? {
            guard let (model, usage) = models.max(by: { lhs, rhs in
                lhs.value.occurrences == rhs.value.occurrences
                    ? lhs.key.id > rhs.key.id
                    : lhs.value.occurrences < rhs.value.occurrences
            }) else {
                return nil
            }
            return ProviderUsageSnapshot.Favorite(
                modelName: model.displayName,
                reasoningEffort: usage.reasoningEfforts.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
                }?.key
            )
        }
    }

    let priceCatalog: UsagePriceCatalog

    func build(
        events: some Sequence<UsageEvent>,
        intervals: UsagePeriodIntervals,
        calendar: Calendar
    ) -> UsageSnapshot {
        var daysByProvider: [UsageProvider: [Date: Accumulator]] = [:]
        var previousDayCost: Decimal = 0
        var previousMonthCost: Decimal = 0

        for event in events {
            let details = event.details
            guard
                intervals.earliestStart <= details.timestamp,
                details.timestamp <= intervals.through,
                let quote = priceCatalog.quote(for: event)
            else {
                continue
            }

            let day = calendar.startOfDay(for: details.timestamp)
            daysByProvider[event.provider, default: [:]][day, default: Accumulator()]
                .add(details, quote: quote)
            if intervals.day.previous.contains(details.timestamp) {
                previousDayCost += quote.costNanodollars
            }
            if intervals.month.previous.contains(details.timestamp) {
                previousMonthCost += quote.costNanodollars
            }
        }

        return UsageSnapshot(
            codex: providerSnapshot(
                from: daysByProvider[.codex] ?? [:],
                intervals: intervals
            ),
            claude: providerSnapshot(
                from: daysByProvider[.claude] ?? [:],
                intervals: intervals
            ),
            previousDayCostUSD: previousDayCost / 1_000_000_000,
            previousMonthCostUSD: previousMonthCost / 1_000_000_000
        )
    }

    private func providerSnapshot(
        from days: [Date: Accumulator],
        intervals: UsagePeriodIntervals
    ) -> ProviderUsageSnapshot {
        var total = Accumulator()
        for day in days.values {
            total.merge(day)
        }
        return ProviderUsageSnapshot(
            favorite: total.favorite,
            today: periodSnapshot(from: days, in: intervals.day.current),
            week: periodSnapshot(from: days, in: intervals.week),
            month: periodSnapshot(from: days, in: intervals.month.current),
            dailyMonth: UsageMonthSnapshot(
                range: intervals.month.current,
                days: days
                    .filter { intervals.month.current.contains($0.key) }
                    .sorted { $0.key < $1.key }
                    .map { date, accumulator in
                        UsageDaySnapshot(
                            date: date,
                            processedTokens: accumulator.processedTokens,
                            costUSD: accumulator.costNanodollars / 1_000_000_000
                        )
                    }
            )
        )
    }

    private func periodSnapshot(
        from days: [Date: Accumulator],
        in interval: Range<Date>
    ) -> UsagePeriodSnapshot {
        var accumulator = Accumulator()
        for (date, day) in days where interval.contains(date) {
            accumulator.merge(day)
        }
        return UsagePeriodSnapshot(
            processedTokens: accumulator.processedTokens,
            costUSD: accumulator.costNanodollars / 1_000_000_000
        )
    }
}
