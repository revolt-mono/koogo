import Foundation

enum UsageSnapshotBuilder {
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
        var models: [UsagePricing.Model: ModelUsage] = [:]

        mutating func add(_ event: UsageEvent, quote: UsagePricing.Quote) {
            processedTokens += Decimal(event.processedTokens)
            costNanodollars += quote.costNanodollars
            models[quote.model, default: ModelUsage()].add(
                reasoningEffort: event.details.reasoningEffort
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

    static func build(
        events: some Sequence<UsageEvent>,
        intervals: UsagePeriodIntervals,
        calendar: Calendar
    ) -> UsageSnapshot {
        var codexDays: [Date: Accumulator] = [:]
        var claudeDays: [Date: Accumulator] = [:]

        for event in events {
            guard let quote = UsagePricing.quote(for: event) else {
                continue
            }
            let day = calendar.startOfDay(for: event.details.timestamp)
            switch event {
            case .codex:
                codexDays[day, default: Accumulator()].add(event, quote: quote)
            case .claude:
                claudeDays[day, default: Accumulator()].add(event, quote: quote)
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

    private static func providerSnapshot(
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

    private static func periodSnapshot(
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
