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
        var usageByDay: [UsagePeriodSnapshot?]

        mutating func add(_ usage: UsageRecord, day: Int) {
            favorite.add(usage.modelTurn)
            var dayUsage = usageByDay[day] ?? UsagePeriodSnapshot()
            dayUsage.add(usage)
            usageByDay[day] = dayUsage
        }

        func snapshot(intervals: UsagePeriodIntervals) -> ProviderUsageSnapshot {
            let days = zip(intervals.last30DayStarts, usageByDay).reversed().compactMap { date, usage in
                usage.map { UsageDaySnapshot(date: date, usage: $0) }
            }
            return ProviderUsageSnapshot(
                favorite: favorite.snapshot(),
                today: usageByDay[0] ?? .init(),
                last7Days: usageByDay.prefix(7).compactMap(\.self).reduce(UsagePeriodSnapshot(), +),
                last30Days: usageByDay.compactMap(\.self).reduce(UsagePeriodSnapshot(), +),
                dailyLast30Days: UsageDailySnapshot(range: intervals.last30Days, days: days)
            )
        }
    }

    private static let order = Provider.allCases

    private let intervals: UsagePeriodIntervals
    private var accumulators: [ProviderAccumulator?]
    private var previous30Days = UsagePeriodSnapshot()

    init(providers: Set<Provider>, intervals: UsagePeriodIntervals) {
        self.intervals = intervals
        let days = [UsagePeriodSnapshot?](repeating: nil, count: intervals.last30DayStarts.count)
        accumulators = Self.order.map { providers.contains($0) ? ProviderAccumulator(usageByDay: days) : nil }
    }

    mutating func add(_ event: UsageEvent) {
        guard let slot = Self.order.firstIndex(of: event.provider), accumulators[slot] != nil else {
            return
        }
        let usage = event.usage
        if let day = intervals.last30DayIndex(containing: usage.timestamp) {
            accumulators[slot]?.add(usage, day: day)
        } else if intervals.previous30Days.contains(usage.timestamp) {
            previous30Days.add(usage)
        }
    }

    var snapshot: UsageSnapshot {
        let included = zip(Self.order, accumulators).compactMap { provider, accumulator in
            accumulator.map { (provider, $0) }
        }
        return UsageSnapshot(
            providers: Dictionary(uniqueKeysWithValues: included.map { ($0, $1.snapshot(intervals: intervals)) }),
            previousDay: included.map { $1.usageByDay[1] ?? .init() }.reduce(UsagePeriodSnapshot(), +),
            previous30Days: previous30Days
        )
    }
}
