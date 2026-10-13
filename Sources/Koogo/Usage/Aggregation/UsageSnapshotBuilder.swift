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

        func snapshot(
            intervals: UsagePeriodIntervals,
            splitsByModel: Bool,
            modelName: (ModelID) -> String
        ) -> ProviderUsageSnapshot {
            let days = intervals.last30DayStarts.indices.reversed().compactMap { day in
                usageByDay[day].isEmpty
                    ? nil : UsageDaySnapshot(date: intervals.last30DayStarts[day], usage: total(day: day))
            }
            return ProviderUsageSnapshot(
                periods: EnumMap { period(dayCount: $0.dayCount, splitsByModel: splitsByModel, modelName: modelName) },
                dailyLast30Days: UsageDailySnapshot(range: intervals.last30Days, days: days)
            )
        }

        private func period(
            dayCount: Int,
            splitsByModel: Bool,
            modelName: (ModelID) -> String
        ) -> ProviderUsagePeriodSnapshot {
            let usageByModel = usageByDay.prefix(dayCount).reduce(into: [:]) { $0.merge($1, uniquingKeysWith: +) }
            let models = usageByModel.filter { $0.value != UsagePeriodSnapshot() }.map { model, usage in
                ModelUsageSnapshot(id: model, modelName: model.map(modelName) ?? "Unattributed", usage: usage)
            }.sorted { lhs, rhs in
                (rhs.usage.costUSD, lhs.id?.rawValue ?? "") < (lhs.usage.costUSD, rhs.id?.rawValue ?? "")
            }
            return ProviderUsagePeriodSnapshot(
                total: usageByModel.values.reduce(UsagePeriodSnapshot(), +),
                models: splitsByModel ? models : nil
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

    /// Names each model through its provider's source; a model the source does not know shows its id.
    func snapshot(sources: EnumMap<Provider, any UsageSource>) -> UsageSnapshot {
        var providers: [Provider: ProviderUsageSnapshot] = [:]
        for case (let provider, let accumulator?) in accumulators.entries {
            let source = sources[provider]
            providers[provider] = accumulator.snapshot(intervals: intervals, splitsByModel: source.splitsUsageByModel) {
                source.modelName($0) ?? $0.rawValue
            }
        }
        return UsageSnapshot(
            providers: providers,
            previousDay: accumulators.entries.compactMap { $1?.total(day: 1) }.reduce(UsagePeriodSnapshot(), +),
            previous30Days: previous30Days
        )
    }
}
