import Foundation

struct UsagePeriodSnapshot: Equatable, Sendable, Encodable {
    private(set) var processedTokens: UInt64 = 0
    private(set) var costUSD: Decimal = 0

    mutating func add(_ usage: UsageRecord) {
        processedTokens = processedTokens.saturatingAdding(usage.processedTokens)
        costUSD += usage.costUSD
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        UsagePeriodSnapshot(
            processedTokens: lhs.processedTokens.saturatingAdding(rhs.processedTokens),
            costUSD: lhs.costUSD + rhs.costUSD
        )
    }
}

struct UsageDaySnapshot: Equatable, Identifiable, Sendable, Encodable {
    let date: Date
    let usage: UsagePeriodSnapshot

    var id: Date { date }
}

struct UsageMonthSnapshot: Equatable, Sendable, Encodable {
    let range: Range<Date>
    let days: [UsageDaySnapshot]
}

struct ProviderUsageSnapshot: Equatable, Sendable, Encodable {
    struct Favorite: Equatable, Sendable, Encodable {
        let modelName: String
        let reasoningEffort: String?
    }

    let favorite: Favorite?
    let today: UsagePeriodSnapshot
    let week: UsagePeriodSnapshot
    let month: UsagePeriodSnapshot
    let dailyMonth: UsageMonthSnapshot
}

enum UsageCostChange: Equatable, Sendable, Encodable {
    case increase(fraction: Decimal)
    case decrease(fraction: Decimal)
    case unchanged

    init(currentUSD: Decimal, previousUSD: Decimal) {
        let signedFraction =
            previousUSD == 0
            ? (currentUSD == 0 ? 0 : 1)
            : (currentUSD - previousUSD) / previousUSD

        if signedFraction > 0 {
            self = .increase(fraction: signedFraction)
        } else if signedFraction < 0 {
            self = .decrease(fraction: -signedFraction)
        } else {
            self = .unchanged
        }
    }
}

struct UsageSummaryPeriodSnapshot: Equatable, Sendable, Encodable {
    let current: UsagePeriodSnapshot
    let costChange: UsageCostChange

    init(
        current: UsagePeriodSnapshot,
        previous: UsagePeriodSnapshot
    ) {
        self.current = current
        costChange = UsageCostChange(currentUSD: current.costUSD, previousUSD: previous.costUSD)
    }
}

struct UsageSummarySnapshot: Equatable, Sendable, Encodable {
    let today: UsageSummaryPeriodSnapshot
    let month: UsageSummaryPeriodSnapshot
}

struct UsageSnapshot: Equatable, Sendable, Encodable {
    let summary: UsageSummarySnapshot
    let providers: [Provider: ProviderUsageSnapshot]

    init(
        providers: [Provider: ProviderUsageSnapshot],
        previousDay: UsagePeriodSnapshot,
        previousMonth: UsagePeriodSnapshot
    ) {
        summary = UsageSummarySnapshot(
            today: UsageSummaryPeriodSnapshot(
                current: providers.values.map(\.today).reduce(UsagePeriodSnapshot(), +),
                previous: previousDay
            ),
            month: UsageSummaryPeriodSnapshot(
                current: providers.values.map(\.month).reduce(UsagePeriodSnapshot(), +),
                previous: previousMonth
            )
        )
        self.providers = providers
    }
}

private extension UInt64 {
    func saturatingAdding(_ other: Self) -> Self {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? .max : sum
    }
}
