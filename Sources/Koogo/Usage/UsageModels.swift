import Foundation

enum UsageProvider: Hashable, Sendable {
    case codex
    case claude
    case piAgent
}

enum UsageModelReference: Hashable, Sendable {
    case codex(id: String, name: String)
    case claude(id: String, name: String)
    case piAgent(provider: String, id: String)
}

struct UsageRecord: Hashable, Sendable {
    struct ModelTurn: Hashable, Sendable {
        let model: UsageModelReference
        let reasoningEffort: String?
    }

    let timestamp: Date
    let processedTokens: UInt64
    let costUSD: Decimal
    let modelTurn: ModelTurn?
}

struct UsageQuote: Sendable {
    let model: UsageModelReference
    let costUSD: Decimal
}

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

struct UsageDailySnapshot: Equatable, Sendable {
    let interval: UsageInterval
    let days: [UsageDaySnapshot]
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    struct Favorite: Equatable, Sendable {
        let modelName: String
        let reasoningEffort: String?
    }

    let favorite: Favorite?
    let last24Hours: UsagePeriodSnapshot
    let last7Days: UsagePeriodSnapshot
    let last30Days: UsagePeriodSnapshot
    let last30DaysByDay: UsageDailySnapshot
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

struct UsageSummaryPeriodSnapshot: Equatable, Sendable {
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

struct UsageSummarySnapshot: Equatable, Sendable {
    let last24Hours: UsageSummaryPeriodSnapshot
    let last30Days: UsageSummaryPeriodSnapshot
}

struct UsageSnapshot: Equatable, Sendable {
    let summary: UsageSummarySnapshot
    let codex: ProviderUsageSnapshot
    let claude: ProviderUsageSnapshot
    let piAgent: ProviderUsageSnapshot

    init(
        codex: ProviderUsageSnapshot,
        claude: ProviderUsageSnapshot,
        piAgent: ProviderUsageSnapshot,
        previous24Hours: UsagePeriodSnapshot,
        previous30Days: UsagePeriodSnapshot
    ) {
        summary = UsageSummarySnapshot(
            last24Hours: UsageSummaryPeriodSnapshot(
                current: codex.last24Hours + claude.last24Hours + piAgent.last24Hours,
                previous: previous24Hours
            ),
            last30Days: UsageSummaryPeriodSnapshot(
                current: codex.last30Days + claude.last30Days + piAgent.last30Days,
                previous: previous30Days
            )
        )
        self.codex = codex
        self.claude = claude
        self.piAgent = piAgent
    }
}
