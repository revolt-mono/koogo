import Foundation

struct UsageSnapshotBuilder {
    private struct ProviderAccumulator {
        var usageByDay: [[ModelID?: UsagePeriodSnapshot]]

        mutating func add(_ usage: UsageRecord, day: Int) {
            usageByDay[day][usage.model, default: UsagePeriodSnapshot()].add(usage)
        }

        func total(days: Range<Int>) -> UsagePeriodSnapshot {
            usageByDay[days].lazy.flatMap(\.values).reduce(UsagePeriodSnapshot(), +)
        }

        func snapshot(intervals: UsagePeriodIntervals, source: any UsageSource) -> ProviderUsageSnapshot {
            let days = intervals.last30DayStarts.indices.reversed().map { day in
                UsageDaySnapshot(date: intervals.last30DayStarts[day], usage: total(days: day..<day + 1))
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
                (rhs.usage.cost, lhs.id?.rawValue ?? "") < (lhs.usage.cost, rhs.id?.rawValue ?? "")
            }
            return ProviderUsagePeriodSnapshot(
                total: usageByModel.values.reduce(UsagePeriodSnapshot(), +),
                models: source.splitsUsageByModel ? models : nil
            )
        }
    }

    private let intervals: UsagePeriodIntervals
    private var accumulators: EnumMap<Provider, ProviderAccumulator?>

    init(providers: Set<Provider>, intervals: UsagePeriodIntervals) {
        self.intervals = intervals
        let days = [[ModelID?: UsagePeriodSnapshot]](repeating: [:], count: intervals.last30DayStarts.count)
        accumulators = EnumMap { providers.contains($0) ? ProviderAccumulator(usageByDay: days) : nil }
    }

    mutating func add(_ event: UsageEvent) {
        if let day = intervals.last30DayIndex(containing: event.record.timestamp) {
            accumulators[event.provider]?.add(event.record, day: day)
        }
    }

    func snapshot(sources: EnumMap<Provider, any UsageSource>) -> UsageSnapshot {
        var providers: [Provider: ProviderUsageSnapshot] = [:]
        for case (let provider, let accumulator?) in accumulators.entries {
            providers[provider] = accumulator.snapshot(intervals: intervals, source: sources[provider])
        }
        func total(days: Range<Int>) -> UsagePeriodSnapshot {
            accumulators.entries.compactMap { $1?.total(days: days) }.reduce(UsagePeriodSnapshot(), +)
        }
        func comparison(_ period: UsagePeriod) -> UsageSummaryPeriodSnapshot {
            let days = period.dayCount
            return UsageSummaryPeriodSnapshot(current: total(days: 0..<days), previous: total(days: days..<2 * days))
        }
        return UsageSnapshot(
            summary: UsageSummarySnapshot(today: comparison(.today), last7Days: comparison(.last7Days)),
            providers: providers
        )
    }
}
