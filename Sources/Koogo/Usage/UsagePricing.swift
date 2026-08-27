import Foundation

struct UsagePriceCatalog: Sendable {
    // Sources, checked 2026-08-26:
    // https://developers.openai.com/api/docs/pricing
    // https://openai.com/index/gpt-5-6
    // https://platform.claude.com/docs/en/about-claude/pricing
    // https://platform.claude.com/docs/en/models/overview
    struct Model: Hashable, Sendable {
        fileprivate let id: String
        let displayName: String
    }

    struct Quote: Sendable {
        let model: Model
        let costNanodollars: Decimal
    }

    private enum CacheWriteRates: Sendable {
        case unsupported
        case fiveMinute(Decimal)
        case byDuration(fiveMinute: Decimal, oneHour: Decimal)
    }

    private struct Rates: Sendable {
        let input: Decimal
        let cachedInput: Decimal
        let cacheWrite: CacheWriteRates
        let output: Decimal

        func cost(for tokens: UsageTokens) -> Decimal? {
            let cacheWriteCost: Decimal
            switch (cacheWrite, tokens.cacheWrite) {
            case (_, .fiveMinute(0)), (_, .byDuration(0, 0)):
                cacheWriteCost = 0
            case
                (.fiveMinute(let rate), .fiveMinute(let amount)),
                (.byDuration(let rate, _), .fiveMinute(let amount)):
                cacheWriteCost = Decimal(amount) * rate
            case (.fiveMinute(let rate), .byDuration(let fiveMinute, 0)):
                cacheWriteCost = Decimal(fiveMinute) * rate
            case (
                .byDuration(let fiveMinuteRate, let oneHourRate),
                .byDuration(let fiveMinute, let oneHour)
            ):
                cacheWriteCost = Decimal(fiveMinute) * fiveMinuteRate
                    + Decimal(oneHour) * oneHourRate
            case (.unsupported, _), (.fiveMinute, .byDuration):
                return nil
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
    }

    private static let codexPrices: [String: CodexModelPrice] = [
        "gpt-5.6-sol": CodexModelPrice(
            displayName: "GPT 5.6 Sol",
            rates: .tiered(
                short: Rates(
                    input: 5_000,
                    cachedInput: 500,
                    cacheWrite: .fiveMinute(6_250),
                    output: 30_000
                ),
                long: Rates(
                    input: 10_000,
                    cachedInput: 1_000,
                    cacheWrite: .fiveMinute(12_500),
                    output: 45_000
                )
            )
        ),
        "gpt-5.6-terra": CodexModelPrice(
            displayName: "GPT 5.6 Terra",
            rates: .tiered(
                short: Rates(
                    input: 2_000,
                    cachedInput: 200,
                    cacheWrite: .fiveMinute(2_500),
                    output: 12_000
                ),
                long: Rates(
                    input: 4_000,
                    cachedInput: 400,
                    cacheWrite: .fiveMinute(5_000),
                    output: 18_000
                )
            )
        ),
        "gpt-5.6-luna": CodexModelPrice(
            displayName: "GPT 5.6 Luna",
            rates: .tiered(
                short: Rates(
                    input: 200,
                    cachedInput: 20,
                    cacheWrite: .fiveMinute(250),
                    output: 1_200
                ),
                long: Rates(
                    input: 400,
                    cachedInput: 40,
                    cacheWrite: .fiveMinute(500),
                    output: 1_800
                )
            )
        ),
        "gpt-5.5": CodexModelPrice(
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
        "gpt-5.4": CodexModelPrice(
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
        "gpt-5.4-mini": CodexModelPrice(
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
        "gpt-5.3-codex": CodexModelPrice(
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

    private static let codexAliases: [String: String] = [
        "gpt-5.6": "gpt-5.6-sol",
        "gpt-daybreak-blue-latest": "gpt-5.6-sol",
        "daybreak-blue-latest": "gpt-5.6-sol",
    ]

    private static let claudePrices: [String: ClaudeModelPrice] = [
        "claude-fable-5": ClaudeModelPrice(
            displayName: "Claude Fable 5",
            standard: Rates(
                input: 10_000,
                cachedInput: 1_000,
                cacheWrite: .byDuration(fiveMinute: 12_500, oneHour: 20_000),
                output: 50_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-mythos-5": ClaudeModelPrice(
            displayName: "Claude Mythos 5",
            standard: Rates(
                input: 10_000,
                cachedInput: 1_000,
                cacheWrite: .byDuration(fiveMinute: 12_500, oneHour: 20_000),
                output: 50_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-5": ClaudeModelPrice(
            displayName: "Claude Opus 5",
            standard: Rates(
                input: 5_000,
                cachedInput: 500,
                cacheWrite: .byDuration(fiveMinute: 6_250, oneHour: 10_000),
                output: 25_000
            ),
            fast: Rates(
                input: 10_000,
                cachedInput: 1_000,
                cacheWrite: .byDuration(fiveMinute: 12_500, oneHour: 20_000),
                output: 50_000
            ),
            supportsUSInference: true
        ),
        "claude-opus-4-8": ClaudeModelPrice(
            displayName: "Claude Opus 4.8",
            standard: Rates(
                input: 5_000,
                cachedInput: 500,
                cacheWrite: .byDuration(fiveMinute: 6_250, oneHour: 10_000),
                output: 25_000
            ),
            fast: Rates(
                input: 10_000,
                cachedInput: 1_000,
                cacheWrite: .byDuration(fiveMinute: 12_500, oneHour: 20_000),
                output: 50_000
            ),
            supportsUSInference: true
        ),
        "claude-opus-4-7": ClaudeModelPrice(
            displayName: "Claude Opus 4.7",
            standard: Rates(
                input: 5_000,
                cachedInput: 500,
                cacheWrite: .byDuration(fiveMinute: 6_250, oneHour: 10_000),
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-4-6": ClaudeModelPrice(
            displayName: "Claude Opus 4.6",
            standard: Rates(
                input: 5_000,
                cachedInput: 500,
                cacheWrite: .byDuration(fiveMinute: 6_250, oneHour: 10_000),
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-opus-4-5-20251101": ClaudeModelPrice(
            displayName: "Claude Opus 4.5",
            standard: Rates(
                input: 5_000,
                cachedInput: 500,
                cacheWrite: .byDuration(fiveMinute: 6_250, oneHour: 10_000),
                output: 25_000
            ),
            fast: nil,
            supportsUSInference: false
        ),
        "claude-sonnet-5": ClaudeModelPrice(
            displayName: "Claude Sonnet 5",
            standard: Rates(
                input: 2_000,
                cachedInput: 200,
                cacheWrite: .byDuration(fiveMinute: 2_500, oneHour: 4_000),
                output: 10_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-sonnet-4-6": ClaudeModelPrice(
            displayName: "Claude Sonnet 4.6",
            standard: Rates(
                input: 3_000,
                cachedInput: 300,
                cacheWrite: .byDuration(fiveMinute: 3_750, oneHour: 6_000),
                output: 15_000
            ),
            fast: nil,
            supportsUSInference: true
        ),
        "claude-sonnet-4-5-20250929": ClaudeModelPrice(
            displayName: "Claude Sonnet 4.5",
            standard: Rates(
                input: 3_000,
                cachedInput: 300,
                cacheWrite: .byDuration(fiveMinute: 3_750, oneHour: 6_000),
                output: 15_000
            ),
            fast: nil,
            supportsUSInference: false
        ),
        "claude-haiku-4-5-20251001": ClaudeModelPrice(
            displayName: "Claude Haiku 4.5",
            standard: Rates(
                input: 1_000,
                cachedInput: 100,
                cacheWrite: .byDuration(fiveMinute: 1_250, oneHour: 2_000),
                output: 5_000
            ),
            fast: nil,
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
            + tokens.cacheWrite.total
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
        case .implicitStandard, .standard: rates = price.standard
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
        var codexDays: [Date: Accumulator] = [:]
        var claudeDays: [Date: Accumulator] = [:]

        for event in events {
            let details = event.details
            guard let quote = priceCatalog.quote(for: event) else {
                continue
            }

            let day = calendar.startOfDay(for: details.timestamp)
            switch event {
            case .codex:
                codexDays[day, default: Accumulator()].add(details, quote: quote)
            case .claude:
                claudeDays[day, default: Accumulator()].add(details, quote: quote)
            }
        }

        return UsageSnapshot(
            codex: providerSnapshot(from: codexDays, intervals: intervals),
            claude: providerSnapshot(from: claudeDays, intervals: intervals),
            previousDay: periodSnapshot(from: codexDays, in: intervals.day.previous)
                + periodSnapshot(from: claudeDays, in: intervals.day.previous),
            previousMonth: periodSnapshot(from: codexDays, in: intervals.month.previous)
                + periodSnapshot(from: claudeDays, in: intervals.month.previous)
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
        var processedTokens: Decimal = 0
        var costNanodollars: Decimal = 0
        for (date, day) in days where interval.contains(date) {
            processedTokens += day.processedTokens
            costNanodollars += day.costNanodollars
        }
        return UsagePeriodSnapshot(
            processedTokens: processedTokens,
            costUSD: costNanodollars / 1_000_000_000
        )
    }
}
