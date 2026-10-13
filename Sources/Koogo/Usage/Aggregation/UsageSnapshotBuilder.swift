import Foundation

struct UsageSnapshotBuilder {
    private struct ProviderAccumulator {
        var usageByDay: [[ModelID?: UsagePeriodSnapshot]]

        mutating func add(_ usage: UsageRecord, day: Int) {
            usageByDay[day][usage.model, default: UsagePeriodSnapshot()].add(usage)
        }

        func total(day: Int) -> UsagePeriodSnapshot {
            usageByDay[day].values.reduce(UsagePeriodSnapshot(), +)
        }

        func snapshot(intervals: UsagePeriodIntervals, source: any UsageSource) -> ProviderUsageSnapshot {
            let days = intervals.last30DayStarts.indices.reversed().map { day in
                UsageDaySnapshot(date: intervals.last30DayStarts[day], usage: total(day: day))
            }
            return ProviderUsageSnapshot(
                periods: EnumMap { period(dayCount: $0.dayCount, source: source) },
                dailyLast30Days: UsageDailySnapshot(range: intervals.last30Days, days: days)
            )
        }

        private func period(dayCount: Int, source: any UsageSource) -> ProviderUsagePeriodSnapshot {
            let usageByModel = usageByDay.prefix(dayCount).reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) }
            let models = usageByModel.filter { $0.value != UsagePeriodSnapshot() }.map { model, usage in
                ModelUsageSnapshot(
                    id: model,
                    modelName: model.map { source.modelName($0) ?? $0.rawValue } ?? "Unattributed",
                    usage: usage
                )
            }.sorted { lhs, rhs in
                (rhs.usage.costUSD, lhs.id?.rawValue ?? "") < (lhs.usage.costUSD, rhs.id?.rawValue ?? "")
            }
            return ProviderUsagePeriodSnapshot(
                total: usageByModel.values.reduce(UsagePeriodSnapshot(), +),
                models: source.splitsUsageByModel ? models : nil
            )
        }
    }

    private let intervals: UsagePeriodIntervals
    private var accumulators: EnumMap<Provider, ProviderAccumulator?>
    private var previous30Days = UsagePeriodSnapshot()

    init(providers: Set<Provider>, intervals: UsagePeriodIntervals) {
        self.intervals = intervals
        let days = [[ModelID?: UsagePeriodSnapshot]](repeating: [:], count: intervals.last30DayStarts.count)
        accumulators = EnumMap { providers.contains($0) ? ProviderAccumulator(usageByDay: days) : nil }
    }

    mutating func add(_ event: UsageEvent) {
        guard accumulators[event.provider] != nil else {
            return
        }
        let usage = event.record
        if let day = intervals.last30DayIndex(containing: usage.timestamp) {
            accumulators[event.provider]?.add(usage, day: day)
        } else if intervals.previous30Days.contains(usage.timestamp) {
            previous30Days.add(usage)
        }
    }

    func snapshot(sources: EnumMap<Provider, any UsageSource>) -> UsageSnapshot {
        var providers: [Provider: ProviderUsageSnapshot] = [:]
        for case (let provider, let accumulator?) in accumulators.entries {
            providers[provider] = accumulator.snapshot(intervals: intervals, source: sources[provider])
        }
        return UsageSnapshot(
            providers: providers,
            previousDay: accumulators.entries.compactMap { $1?.total(day: 1) }.reduce(UsagePeriodSnapshot(), +),
            previous30Days: previous30Days
        )
    }
}
