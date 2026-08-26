import Foundation

struct UsagePriceCatalog: Sendable {
    // Sources, checked 2026-08-25:
    // https://developers.openai.com/api/docs/pricing
    // https://platform.claude.com/docs/en/about-claude/pricing
    // https://platform.claude.com/docs/en/models/overview
    static let pricingAsOf = "2026-08-25"

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
        case shortOnly(Rates)

        func rates(for inputTokens: Int64) -> Rates? {
            switch self {
            case .flat(let rates):
                rates
            case .tiered(let short, let long):
                inputTokens > 272_000 ? long : short
            case .shortOnly(let rates):
                inputTokens > 272_000 ? nil : rates
            }
        }
    }

    private struct CodexModelPrice: Sendable {
        let standard: ContextRates
        let fast: ContextRates?
        let flex: ContextRates?

        init(
            standard: ContextRates,
            fast: ContextRates? = nil,
            flex: ContextRates? = nil
        ) {
            self.standard = standard
            self.fast = fast
            self.flex = flex
        }
    }

    private struct ClaudeModelPrice: Sendable {
        let standard: Rates
        let fast: Rates?
        let supportsUSInference: Bool

        init(
            _ standard: Rates,
            fast: Rates? = nil,
            supportsUSInference: Bool = true
        ) {
            self.standard = standard
            self.fast = fast
            self.supportsUSInference = supportsUSInference
        }
    }

    private static let codexPrices: [String: CodexModelPrice] = [
        "gpt-5.6-sol": CodexModelPrice(
            standard: .tiered(
                short: Rates(4_000, 400, 5_000, 20_000),
                long: Rates(8_000, 800, 10_000, 30_000)
            ),
            fast: .tiered(
                short: Rates(8_000, 800, 10_000, 40_000),
                long: Rates(16_000, 1_600, 20_000, 60_000)
            ),
            flex: .tiered(
                short: Rates(2_000, 200, 2_500, 10_000),
                long: Rates(4_000, 400, 5_000, 15_000)
            )
        ),
        "gpt-5.6-terra": CodexModelPrice(
            standard: .tiered(
                short: Rates(2_000, 200, 2_500, 12_000),
                long: Rates(4_000, 400, 5_000, 18_000)
            ),
            fast: .tiered(
                short: Rates(4_000, 400, 5_000, 24_000),
                long: Rates(8_000, 800, 10_000, 36_000)
            ),
            flex: .tiered(
                short: Rates(1_000, 100, 1_250, 6_000),
                long: Rates(2_000, 200, 2_500, 9_000)
            )
        ),
        "gpt-5.6-luna": CodexModelPrice(
            standard: .tiered(
                short: Rates(200, 20, 250, 1_200),
                long: Rates(400, 40, 500, 1_800)
            ),
            fast: .tiered(
                short: Rates(400, 40, 500, 2_400),
                long: Rates(800, 80, 1_000, 3_600)
            ),
            flex: .tiered(
                short: Rates(100, 10, 125, 600),
                long: Rates(200, 20, 250, 900)
            )
        ),
        "gpt-5.5": CodexModelPrice(
            standard: .tiered(
                short: Rates(5_000, 500, nil, 30_000),
                long: Rates(10_000, 1_000, nil, 45_000)
            ),
            fast: .shortOnly(Rates(12_500, 1_250, nil, 75_000)),
            flex: .tiered(
                short: Rates(2_500, 250, nil, 15_000),
                long: Rates(5_000, 500, nil, 22_500)
            )
        ),
        "gpt-5.4": CodexModelPrice(
            standard: .tiered(
                short: Rates(2_500, 250, nil, 15_000),
                long: Rates(5_000, 500, nil, 22_500)
            ),
            fast: .shortOnly(Rates(5_000, 500, nil, 30_000)),
            flex: .tiered(
                short: Rates(1_250, 130, nil, 7_500),
                long: Rates(2_500, 250, nil, 11_250)
            )
        ),
        "gpt-5.4-mini": CodexModelPrice(
            standard: .flat(Rates(750, 75, nil, 4_500)),
            fast: .flat(Rates(1_500, 150, nil, 9_000)),
            flex: .flat(Rates(375, Decimal(375) / 10, nil, 2_250))
        ),
        "gpt-5.3-codex": CodexModelPrice(
            standard: .flat(Rates(1_750, 175, nil, 14_000)),
            fast: .flat(Rates(3_500, 350, nil, 28_000))
        ),
    ]

    private static let codexAliases: [String: String] = [
        "gpt-5.6": "gpt-5.6-sol",
        "gpt-daybreak-blue-latest": "gpt-5.6-sol",
        "daybreak-blue-latest": "gpt-5.6-sol",
    ]

    private static let claudePrices: [String: ClaudeModelPrice] = [
        "claude-fable-5": ClaudeModelPrice(Rates(10_000, 1_000, 12_500, 20_000, 50_000)),
        "claude-mythos-5": ClaudeModelPrice(Rates(10_000, 1_000, 12_500, 20_000, 50_000)),
        "claude-opus-5": ClaudeModelPrice(
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            fast: Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-opus-4-8": ClaudeModelPrice(
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            fast: Rates(10_000, 1_000, 12_500, 20_000, 50_000)
        ),
        "claude-opus-4-7": ClaudeModelPrice(Rates(5_000, 500, 6_250, 10_000, 25_000)),
        "claude-opus-4-6": ClaudeModelPrice(Rates(5_000, 500, 6_250, 10_000, 25_000)),
        "claude-opus-4-5-20251101": ClaudeModelPrice(
            Rates(5_000, 500, 6_250, 10_000, 25_000),
            supportsUSInference: false
        ),
        "claude-sonnet-5": ClaudeModelPrice(Rates(2_000, 200, 2_500, 4_000, 10_000)),
        "claude-sonnet-4-6": ClaudeModelPrice(Rates(3_000, 300, 3_750, 6_000, 15_000)),
        "claude-sonnet-4-5-20250929": ClaudeModelPrice(
            Rates(3_000, 300, 3_750, 6_000, 15_000),
            supportsUSInference: false
        ),
        "claude-haiku-4-5-20251001": ClaudeModelPrice(
            Rates(1_000, 100, 1_250, 2_000, 5_000),
            supportsUSInference: false
        ),
    ]

    private static let claudeAliases: [String: String] = [
        "claude-opus-4-5": "claude-opus-4-5-20251101",
        "claude-sonnet-4-5": "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5": "claude-haiku-4-5-20251001",
    ]

    func costNanodollars(for event: UsageEvent) -> Decimal? {
        switch event {
        case .codex(let event):
            codexCost(event)
        case .claude(let event):
            claudeCost(event)
        }
    }

    private func codexCost(_ event: UsageEvent.Codex) -> Decimal? {
        let model = Self.codexAliases[event.details.model] ?? event.details.model
        guard let price = Self.codexPrices[model] else {
            return nil
        }

        let contextRates: ContextRates?
        switch event.serviceTier {
        case .standard: contextRates = price.standard
        case .fast: contextRates = price.fast
        case .flex: contextRates = price.flex
        }
        let tokens = event.details.tokens
        let inputTokens = tokens.uncachedInput
            + tokens.cachedInput
            + tokens.cacheWrite5MinuteInput
        return contextRates?.rates(for: inputTokens)?.cost(for: tokens)
    }

    private func claudeCost(_ event: UsageEvent.Claude) -> Decimal? {
        let model = Self.claudeAliases[event.details.model] ?? event.details.model
        guard let price = Self.claudePrices[model] else {
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

        return cost + Decimal(event.webSearchRequests) * 10_000_000
    }
}

struct UsageSnapshotBuilder {
    private struct Accumulator {
        var processedTokens: Decimal = 0
        var costNanodollars: Decimal = 0
        var modelCounts: [String: Int] = [:]
        var effortCounts: [String: Int] = [:]

        mutating func add(_ details: UsageEvent.Details, cost: Decimal) {
            processedTokens += Decimal(details.tokens.processed)
            costNanodollars += cost
            modelCounts[details.model, default: 0] += 1
            if let effort = details.reasoningEffort {
                effortCounts[effort, default: 0] += 1
            }
        }

        mutating func merge(_ other: Accumulator) {
            processedTokens += other.processedTokens
            costNanodollars += other.costNanodollars
            modelCounts.merge(other.modelCounts, uniquingKeysWith: +)
            effortCounts.merge(other.effortCounts, uniquingKeysWith: +)
        }
    }

    let priceCatalog: UsagePriceCatalog

    func build(
        events: some Sequence<UsageEvent>,
        at date: Date,
        intervals: UsagePeriodIntervals,
        calendar: Calendar
    ) -> UsageSnapshot {
        var daysByProvider: [UsageProvider: [Date: Accumulator]] = [:]

        for event in events {
            let details = event.details
            guard
                intervals.earliestStart <= details.timestamp,
                details.timestamp <= date,
                let cost = priceCatalog.costNanodollars(for: event)
            else {
                continue
            }

            let day = calendar.startOfDay(for: details.timestamp)
            daysByProvider[event.provider, default: [:]][day, default: Accumulator()]
                .add(details, cost: cost)
        }

        return UsageSnapshot(
            validUntil: intervals.today.end,
            codex: providerSnapshot(from: daysByProvider[.codex] ?? [:], intervals: intervals),
            claude: providerSnapshot(from: daysByProvider[.claude] ?? [:], intervals: intervals)
        )
    }

    private func providerSnapshot(
        from days: [Date: Accumulator],
        intervals: UsagePeriodIntervals
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            today: periodSnapshot(from: days, in: intervals.today),
            week: periodSnapshot(from: days, in: intervals.week),
            month: periodSnapshot(from: days, in: intervals.month),
            dailyMonth: UsageMonthSnapshot(
                interval: intervals.month,
                days: days
                    .filter { intervals.month.contains($0.key) }
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
        in interval: DateInterval
    ) -> UsagePeriodSnapshot {
        var accumulator = Accumulator()
        for (date, day) in days where interval.contains(date) {
            accumulator.merge(day)
        }

        return UsagePeriodSnapshot(
            processedTokens: accumulator.processedTokens,
            costUSD: accumulator.costNanodollars / 1_000_000_000,
            favoriteModel: favorite(in: accumulator.modelCounts),
            favoriteReasoningEffort: favorite(in: accumulator.effortCounts)
        )
    }

    private func favorite(in counts: [String: Int]) -> String? {
        counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}
