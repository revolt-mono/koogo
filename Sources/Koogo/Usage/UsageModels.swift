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

struct ProviderUsageSnapshot: Equatable, Sendable {
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

struct UsageCostComparison: Equatable, Sendable {
    let currentUSD: Decimal
    let previousUSD: Decimal

    var change: UsageCostChange {
        UsageCostChange(currentUSD: currentUSD, previousUSD: previousUSD)
    }
}

struct UsageCostChange: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case increase
        case decrease
        case unchanged
    }

    let direction: Direction
    let fraction: Decimal

    init(currentUSD: Decimal, previousUSD: Decimal) {
        let signedFraction = previousUSD == 0
            ? (currentUSD == 0 ? 0 : 1)
            : (currentUSD - previousUSD) / previousUSD

        if signedFraction > 0 {
            direction = .increase
            fraction = signedFraction
        } else if signedFraction < 0 {
            direction = .decrease
            fraction = -signedFraction
        } else {
            direction = .unchanged
            fraction = 0
        }
    }
}

struct UsageSummaryPeriodSnapshot: Equatable, Sendable {
    let processedTokens: Decimal
    let cost: UsageCostComparison

    init(
        current: UsagePeriodSnapshot,
        previous: UsagePeriodSnapshot
    ) {
        processedTokens = current.processedTokens
        cost = UsageCostComparison(
            currentUSD: current.costUSD,
            previousUSD: previous.costUSD
        )
    }
}

struct UsageSummarySnapshot: Equatable, Sendable {
    let today: UsageSummaryPeriodSnapshot
    let month: UsageSummaryPeriodSnapshot
}

struct UsageSnapshot: Equatable, Sendable {
    let summary: UsageSummarySnapshot
    let codex: ProviderUsageSnapshot
    let claude: ProviderUsageSnapshot

    init(
        codex: ProviderUsageSnapshot,
        claude: ProviderUsageSnapshot,
        previousDay: UsagePeriodSnapshot,
        previousMonth: UsagePeriodSnapshot
    ) {
        summary = UsageSummarySnapshot(
            today: UsageSummaryPeriodSnapshot(
                current: codex.today + claude.today,
                previous: previousDay
            ),
            month: UsageSummaryPeriodSnapshot(
                current: codex.month + claude.month,
                previous: previousMonth
            )
        )
        self.codex = codex
        self.claude = claude
    }
}

struct UsageLogLocations: Sendable {
    let codexSessions: URL
    let codexArchivedSessions: URL
    let claudeProjects: URL

    static var standard: UsageLogLocations {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return UsageLogLocations(
            codexSessions: home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
            codexArchivedSessions: home.appending(path: ".codex/archived_sessions", directoryHint: .isDirectory),
            claudeProjects: home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        )
    }
}

struct UsageTokens: Hashable, Sendable {
    enum CacheWrite: Hashable, Sendable {
        case fiveMinute(Int64)
        case byDuration(fiveMinute: Int64, oneHour: Int64)

        var total: Int64 {
            switch self {
            case .fiveMinute(let tokens):
                tokens
            case .byDuration(let fiveMinute, let oneHour):
                fiveMinute + oneHour
            }
        }
    }

    let uncachedInput: Int64
    let cachedInput: Int64
    let cacheWrite: CacheWrite
    let output: Int64
    let processed: Int64
}

enum UsageEvent: Sendable {
    struct Details: Sendable {
        let timestamp: Date
        let model: String
        let reasoningEffort: String?
        let tokens: UsageTokens
    }

    struct Codex: Sendable {
        let threadID: String
        let turnID: String?
        let ordinal: UInt64?
        let details: Details
        let reasoningOutput: Int64
        let cumulativeTotal: Int64
    }

    struct Claude: Sendable {
        enum Speed: Sendable {
            case implicitStandard
            case standard
            case fast
        }

        let messageID: String
        let requestID: String
        let details: Details
        let speed: Speed
        let inferenceGeo: String?
        let webSearchRequests: Int64

        var metadataCompleteness: Int {
            let explicitSpeed = switch speed {
            case .implicitStandard: 0
            case .standard, .fast: 1
            }
            let explicitCacheDuration = switch details.tokens.cacheWrite {
            case .fiveMinute: 0
            case .byDuration: 1
            }
            return explicitSpeed
                + explicitCacheDuration
                + (details.reasoningEffort == nil ? 0 : 1)
        }
    }

    enum ID: Hashable, Sendable {
        case codex(
            threadID: String,
            turnID: String?,
            ordinal: UInt64?,
            timestamp: Date,
            model: String,
            tokens: UsageTokens,
            reasoningOutput: Int64,
            cumulativeTotal: Int64
        )
        case claude(messageID: String, requestID: String)
    }

    case codex(Codex)
    case claude(Claude)

    var id: ID {
        switch self {
        case .codex(let event):
            return .codex(
                threadID: event.threadID,
                turnID: event.turnID,
                ordinal: event.ordinal,
                timestamp: event.details.timestamp,
                model: event.details.model,
                tokens: event.details.tokens,
                reasoningOutput: event.reasoningOutput,
                cumulativeTotal: event.cumulativeTotal
            )
        case .claude(let event):
            return .claude(messageID: event.messageID, requestID: event.requestID)
        }
    }

    var details: Details {
        switch self {
        case .codex(let event): event.details
        case .claude(let event): event.details
        }
    }

    func isPreferred(over existing: UsageEvent) -> Bool {
        guard case .claude(let candidate) = self, case .claude(let existing) = existing else {
            return false
        }
        if candidate.details.tokens.output != existing.details.tokens.output {
            return candidate.details.tokens.output > existing.details.tokens.output
        }

        let candidateMetadata = candidate.metadataCompleteness
        let existingMetadata = existing.metadataCompleteness
        if candidateMetadata != existingMetadata {
            return candidateMetadata > existingMetadata
        }
        if candidate.details.tokens.processed != existing.details.tokens.processed {
            return candidate.details.tokens.processed > existing.details.tokens.processed
        }
        return candidate.details.timestamp > existing.details.timestamp
    }
}

struct UsagePeriodIntervals {
    struct Comparison {
        let current: Range<Date>
        let previous: Range<Date>

        fileprivate init(
            component: Calendar.Component,
            containing date: Date,
            calendar: Calendar
        ) {
            guard
                let current = calendar.dateInterval(of: component, for: date),
                let previousDate = calendar.date(byAdding: component, value: -1, to: current.start),
                let previous = calendar.dateInterval(of: component, for: previousDate)
            else {
                preconditionFailure("calendar must provide current and previous period intervals")
            }

            self.current = current.start..<current.end
            self.previous = previous.start..<previous.end
        }
    }

    let day: Comparison
    let week: Range<Date>
    let month: Comparison

    init(containing date: Date, calendar: Calendar) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            preconditionFailure("calendar must provide a week interval")
        }

        day = Comparison(component: .day, containing: date, calendar: calendar)
        self.week = week.start..<week.end
        month = Comparison(component: .month, containing: date, calendar: calendar)
    }
}

func parseUsageTimestamp(_ value: String) -> Date? {
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
    }
    return try? Date.ISO8601FormatStyle().parse(value)
}
