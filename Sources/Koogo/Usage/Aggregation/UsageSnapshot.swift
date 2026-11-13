import Foundation

struct UsagePeriodSnapshot: Equatable, Sendable, Encodable {
  private(set) var processedTokens: UInt64 = 0
  private(set) var cost = Picodollars.zero

  static func +(lhs: Self, rhs: Self) -> Self {
    UsagePeriodSnapshot(
      processedTokens: lhs.processedTokens.saturatingAdding(rhs.processedTokens),
      cost: lhs.cost + rhs.cost,
    )
  }

  mutating func add(_ usage: UsageRecord) {
    processedTokens = processedTokens.saturatingAdding(usage.processedTokens)
    cost += usage.cost
  }
}

struct UsageDaySnapshot: Equatable, Sendable, Encodable {
  let date: Date
  let usage: UsagePeriodSnapshot
}

struct ProviderUsagePeriodSnapshot: Equatable, Sendable, Encodable {
  let total: UsagePeriodSnapshot
  let models: [ModelUsageSnapshot]?
}

struct ModelUsageSnapshot: Equatable, Identifiable, Sendable, Encodable {
  let id: ModelID?
  let modelName: String
  let usage: UsagePeriodSnapshot
}

struct ProviderUsageSnapshot: Equatable, Sendable, Encodable {
  let periods: EnumMap<UsagePeriod, ProviderUsagePeriodSnapshot>
  /// oldest first, including days without events.
  let dailyLast30Days: [UsageDaySnapshot]
}

enum UsageCostChange: Equatable, Sendable, Encodable {
  case increase(fraction: Decimal)
  case decrease(fraction: Decimal)
  case unchanged

  init(current: Picodollars, previous: Picodollars) {
    let current = Decimal(current.rawValue)
    let previous = Decimal(previous.rawValue)
    self =
      switch (current, previous) {
      case (0, 0): .unchanged
      case (_, 0): .increase(fraction: 1)
      case _ where current > previous: .increase(fraction: (current - previous) / previous)
      case _ where current < previous: .decrease(fraction: (previous - current) / previous)
      default: .unchanged
      }
  }
}

struct UsageSummaryPeriodSnapshot: Equatable, Sendable, Encodable {
  init(current: UsagePeriodSnapshot, previous: UsagePeriodSnapshot) {
    self.current = current
    costChange = UsageCostChange(current: current.cost, previous: previous.cost)
  }

  let current: UsagePeriodSnapshot
  let costChange: UsageCostChange
}

struct UsageSummarySnapshot: Equatable, Sendable, Encodable {
  let today: UsageSummaryPeriodSnapshot
  let last7Days: UsageSummaryPeriodSnapshot
}

struct UsageSnapshot: Equatable, Sendable, Encodable {
  let summary: UsageSummarySnapshot
  let providers: [Provider: ProviderUsageSnapshot]
}
