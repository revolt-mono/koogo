import Foundation

struct UsageSnapshotBuilder {
  init(providers: [Provider], intervals: UsagePeriodIntervals) {
    self.intervals = intervals
    usage = EnumMap { providers.contains($0) ? DailyUsage() : nil }
  }

  mutating func add(_ event: UsageEvent) {
    guard let day = intervals.last30DayIndex(containing: event.record.timestamp) else {
      return
    }
    usage[event.provider]?.add(event.record, day: day)
  }

  func snapshot(modelNames: UsageModelNames) -> UsageSnapshot {
    var providers = [Provider: ProviderUsageSnapshot]()
    for case (let provider, let daily?) in usage.entries {
      providers[provider] = ProviderUsageSnapshot(
        periods: EnumMap { period in
          let days = 0..<period.dayCount
          return ProviderUsagePeriodSnapshot(
            total: daily.total(days: days),
            models: provider.splitsUsageByModel
              ? daily.models(days: days) { modelNames.name(of: $0, billedBy: provider) }
              : nil,
          )
        },
        dailyLast30Days: intervals.last30DayStarts.enumerated().reversed().map { day, start in
          UsageDaySnapshot(date: start, usage: daily.total(days: day..<day + 1))
        },
      )
    }
    let tracked = usage.entries.compactMap(\.value)
    func total(days: Range<Int>) -> UsagePeriodSnapshot {
      tracked.reduce(UsagePeriodSnapshot()) { $0 + $1.total(days: days) }
    }
    func comparison(_ period: UsagePeriod) -> UsageSummaryPeriodSnapshot {
      let days = period.dayCount
      return UsageSummaryPeriodSnapshot(current: total(days: 0..<days), previous: total(days: days..<2 * days))
    }
    return UsageSnapshot(
      summary: UsageSummarySnapshot(today: comparison(.today), last7Days: comparison(.last7Days)),
      providers: providers,
    )
  }

  private let intervals: UsagePeriodIntervals
  private var usage: EnumMap<Provider, DailyUsage?>
}

private struct DailyUsage {
  mutating func add(_ record: UsageRecord, day: Int) {
    usageByModel[record.model, default: Self.unusedDays][day].add(record)
  }

  func total(days: Range<Int>) -> UsagePeriodSnapshot {
    usageByModel.values.reduce(UsagePeriodSnapshot()) { $0 + $1[days].reduce(UsagePeriodSnapshot(), +) }
  }

  func models(days: Range<Int>, named name: (ModelID) -> String) -> [ModelUsageSnapshot] {
    usageByModel.compactMap { model, usageByDay in
      let usage = usageByDay[days].reduce(UsagePeriodSnapshot(), +)
      return usage.isEmpty
        ? nil
        : ModelUsageSnapshot(id: model, modelName: model.map(name) ?? "Unattributed", usage: usage)
    }.sorted { lhs, rhs in
      (rhs.usage.cost, lhs.id?.rawValue ?? "") < (lhs.usage.cost, rhs.id?.rawValue ?? "")
    }
  }

  private static let unusedDays = Array(repeating: UsagePeriodSnapshot(), count: UsagePeriod.last30Days.dayCount)

  private var usageByModel = [ModelID?: [UsagePeriodSnapshot]]()
}
