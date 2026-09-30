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
    }

    private struct FavoriteAccumulator {
        var models: [UsageModelReference: ModelUsage] = [:]

        mutating func add(_ turn: UsageRecord.ModelTurn?) {
            if let turn {
                models[turn.model, default: ModelUsage()].add(
                    reasoningEffort: turn.reasoningEffort
                )
            }
        }

        func snapshot() -> ProviderUsageSnapshot.Favorite? {
            guard
                let (model, usage) = models.max(by: { lhs, rhs in
                    lhs.value.occurrences == rhs.value.occurrences
                        ? lhs.key.id > rhs.key.id
                        : lhs.value.occurrences < rhs.value.occurrences
                })
            else {
                return nil
            }
            return ProviderUsageSnapshot.Favorite(
                modelName: model.name,
                reasoningEffort: usage.reasoningEfforts.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
                }?.key
            )
        }
    }

    private struct ProviderAccumulator {
        var favorite = FavoriteAccumulator()
        var usageByDay: [Date: UsagePeriodSnapshot] = [:]

        mutating func add(_ usage: UsageRecord, intervals: UsagePeriodIntervals) {
            guard let day = intervals.last30Day(containing: usage.timestamp) else {
                return
            }
            favorite.add(usage.modelTurn)
            usageByDay[day, default: .init()].add(usage)
        }

        func snapshot(intervals: UsagePeriodIntervals) -> ProviderUsageSnapshot {
            let days = usageByDay.sorted { $0.key < $1.key }.map {
                UsageDaySnapshot(date: $0.key, usage: $0.value)
            }
            return ProviderUsageSnapshot(
                favorite: favorite.snapshot(),
                today: usageByDay[intervals.today] ?? .init(),
                last7Days: days.lazy.filter { $0.date >= intervals.last7DaysStart }
                    .map(\.usage).reduce(UsagePeriodSnapshot(), +),
                last30Days: usageByDay.values.reduce(UsagePeriodSnapshot(), +),
                dailyLast30Days: UsageDailySnapshot(range: intervals.last30Days, days: days)
            )
        }
    }

    static func build(
        events: some Sequence<UsageEvent>,
        providers: Set<Provider> = Set(Provider.allCases),
        intervals: UsagePeriodIntervals
    ) -> UsageSnapshot {
        var accumulators = Dictionary(uniqueKeysWithValues: providers.map { ($0, ProviderAccumulator()) })
        var previous30Days = UsagePeriodSnapshot()

        for event in events where providers.contains(event.provider) {
            let usage = event.usage
            accumulators[event.provider]?.add(usage, intervals: intervals)
            if intervals.previous30Days.contains(usage.timestamp) {
                previous30Days.add(usage)
            }
        }

        return UsageSnapshot(
            providers: accumulators.mapValues { $0.snapshot(intervals: intervals) },
            previousDay: accumulators.values.map { $0.usageByDay[intervals.yesterday] ?? .init() }
                .reduce(UsagePeriodSnapshot(), +),
            previous30Days: previous30Days
        )
    }
}
