import Foundation

struct UsageSnapshotBuilder {
    /// each model's usage per day, newest day first.
    private typealias DailyUsage = [ModelID?: [UsagePeriodSnapshot]]

    private static let unusedDays = Array(repeating: UsagePeriodSnapshot(), count: UsagePeriod.last30Days.dayCount)

    private let intervals: UsagePeriodIntervals
    private var usage: EnumMap<Provider, DailyUsage?>

    init(providers: [Provider], intervals: UsagePeriodIntervals) {
        self.intervals = intervals
        usage = EnumMap { providers.contains($0) ? [:] : nil }
    }

    mutating func add(_ event: UsageEvent) {
        guard let day = intervals.last30DayIndex(containing: event.record.timestamp) else {
            return
        }
        usage[event.provider]?[event.record.model, default: Self.unusedDays][day].add(event.record)
    }

    func snapshot(sources: EnumMap<Provider, any UsageSource>) -> UsageSnapshot {
        var providers: [Provider: ProviderUsageSnapshot] = [:]
        for case (let provider, let daily?) in usage.entries {
            providers[provider] = snapshot(of: daily, source: sources[provider])
        }
        let tracked = usage.entries.compactMap(\.value)
        func total(days: Range<Int>) -> UsagePeriodSnapshot {
            tracked.reduce(UsagePeriodSnapshot()) { $0 + Self.total($1, days: days) }
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

    private func snapshot(of daily: DailyUsage, source: any UsageSource) -> ProviderUsageSnapshot {
        let days = intervals.last30DayStarts.enumerated().reversed().map { day, start in
            UsageDaySnapshot(date: start, usage: Self.total(daily, days: day..<day + 1))
        }
        return ProviderUsageSnapshot(
            periods: EnumMap { Self.period(daily, dayCount: $0.dayCount, source: source) },
            dailyLast30Days: days
        )
    }

    private static func period(
        _ daily: DailyUsage,
        dayCount: Int,
        source: any UsageSource
    ) -> ProviderUsagePeriodSnapshot {
        let usageByModel = daily.map { model, days in
            (model: model, usage: days.prefix(dayCount).reduce(UsagePeriodSnapshot(), +))
        }
        let models = usageByModel.filter { $0.usage != UsagePeriodSnapshot() }.map { model, usage in
            ModelUsageSnapshot(
                id: model,
                modelName: model.map { source.modelName($0) ?? $0.rawValue } ?? "Unattributed",
                usage: usage
            )
        }.sorted { lhs, rhs in
            (rhs.usage.cost, lhs.id?.rawValue ?? "") < (lhs.usage.cost, rhs.id?.rawValue ?? "")
        }
        return ProviderUsagePeriodSnapshot(
            total: usageByModel.reduce(UsagePeriodSnapshot()) { $0 + $1.usage },
            models: source.splitsUsageByModel ? models : nil
        )
    }

    private static func total(_ daily: DailyUsage, days: Range<Int>) -> UsagePeriodSnapshot {
        daily.values.reduce(UsagePeriodSnapshot()) { $0 + $1[days].reduce(UsagePeriodSnapshot(), +) }
    }
}
