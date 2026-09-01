import Foundation

struct UsagePeriodSnapshot: Equatable, Sendable {
    let processedTokens: Decimal
    let costUSD: Decimal

    static let zero = UsagePeriodSnapshot(
        processedTokens: 0,
        costUSD: 0
    )

    static func + (lhs: Self, rhs: Self) -> Self {
        UsagePeriodSnapshot(
            processedTokens: lhs.processedTokens + rhs.processedTokens,
            costUSD: lhs.costUSD + rhs.costUSD
        )
    }
}

struct UsageDaySnapshot: Equatable, Identifiable, Sendable {
    let date: Date
    let processedTokens: Decimal
    let costUSD: Decimal

    var id: Date { date }
}

struct UsageMonthSnapshot: Equatable, Sendable {
    let range: Range<Date>
    let days: [UsageDaySnapshot]
}

struct ProviderUsageSnapshot: Sendable {
    struct Favorite: Equatable, Sendable {
        let modelName: String
        let reasoningEffort: String?
    }

    let favorite: Favorite?
    let today: UsagePeriodSnapshot
    let week: UsagePeriodSnapshot
    let month: UsagePeriodSnapshot
    let dailyMonth: UsageMonthSnapshot
}

enum UsageCostChange: Equatable, Sendable {
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

struct UsageSummaryPeriodSnapshot: Sendable {
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

struct UsageSummarySnapshot: Sendable {
    let today: UsageSummaryPeriodSnapshot
    let month: UsageSummaryPeriodSnapshot
}

struct UsageSnapshot: Sendable {
    let summary: UsageSummarySnapshot
    let codex: ProviderUsageSnapshot
    let claude: ProviderUsageSnapshot
    let piAgent: ProviderUsageSnapshot

    init(
        codex: ProviderUsageSnapshot,
        claude: ProviderUsageSnapshot,
        piAgent: ProviderUsageSnapshot,
        previousDay: UsagePeriodSnapshot,
        previousMonth: UsagePeriodSnapshot
    ) {
        summary = UsageSummarySnapshot(
            today: UsageSummaryPeriodSnapshot(
                current: codex.today + claude.today + piAgent.today,
                previous: previousDay
            ),
            month: UsageSummaryPeriodSnapshot(
                current: codex.month + claude.month + piAgent.month,
                previous: previousMonth
            )
        )
        self.codex = codex
        self.claude = claude
        self.piAgent = piAgent
    }
}
