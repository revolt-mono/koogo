import Foundation

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
    }

    private struct FavoriteAccumulator {
        var models: [ModelID: ModelUsage] = [:]

        mutating func add(_ turn: UsageRecord.ModelTurn?) {
            if let turn {
                models[turn.model, default: ModelUsage()].add(reasoningEffort: turn.reasoningEffort)
            }
        }

        func snapshot(modelName: (ModelID) -> String) -> ProviderUsageSnapshot.Favorite? {
            guard
                let (model, usage) = models.max(by: { lhs, rhs in
                    lhs.value.occurrences == rhs.value.occurrences
                        ? lhs.key.rawValue > rhs.key.rawValue
                        : lhs.value.occurrences < rhs.value.occurrences
                })
            else {
                return nil
            }
            return ProviderUsageSnapshot.Favorite(
                modelName: modelName(model),
                reasoningEffort: usage.reasoningEfforts.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
                }?.key
            )
        }
    }

    private struct ProviderAccumulator {
        var favorite = FavoriteAccumulator()
        var usageByDay: [[ModelID?: UsagePeriodSnapshot]]

        mutating func add(_ usage: UsageRecord, day: Int) {
            favorite.add(usage.modelTurn)
            usageByDay[day][usage.modelTurn?.model, default: UsagePeriodSnapshot()].add(usage)
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
                favorite: favorite.snapshot(modelName: modelName),
                periods: EnumMap { period in
                    let usageByModel = usageByDay.prefix(period.dayCount).reduce(into: [:]) {
                        $0.merge($1, uniquingKeysWith: +)
                    }
                    let models = usageByModel.filter { $0.value != UsagePeriodSnapshot() }.map { model, usage in
                        ModelUsageSnapshot(id: model, modelName: model.map(modelName) ?? "Unattributed", usage: usage)
                    }.sorted { lhs, rhs in
                        lhs.usage.costUSD == rhs.usage.costUSD
                            ? (lhs.id?.rawValue ?? "") < (rhs.id?.rawValue ?? "")
                            : lhs.usage.costUSD > rhs.usage.costUSD
                    }
                    return ProviderUsagePeriodSnapshot(
                        total: usageByModel.values.reduce(UsagePeriodSnapshot(), +),
                        models: splitsByModel ? models : nil
                    )
                },
                dailyLast30Days: UsageDailySnapshot(range: intervals.last30Days, days: days)
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
        let included = accumulators.entries.compactMap { provider, accumulator in
            accumulator.map { (provider, $0) }
        }
        return UsageSnapshot(
            providers: Dictionary(
                uniqueKeysWithValues: included.map { provider, accumulator in
                    let source = sources[provider]
                    return (
                        provider,
                        accumulator.snapshot(intervals: intervals, splitsByModel: source.splitsUsageByModel) {
                            source.modelName($0) ?? $0.rawValue
                        }
                    )
                }
            ),
            previousDay: included.map { $1.total(day: 1) }.reduce(UsagePeriodSnapshot(), +),
            previous30Days: previous30Days
        )
    }
}
