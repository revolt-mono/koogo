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
    let processedTokens: Int64
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
        let signedFraction =
            previousUSD == 0
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

struct UsageLocations: Sendable {
    struct Logs: Sendable {
        struct Codex: Sendable {
            let sessions: URL
            let archivedSessions: URL
        }

        let codex: Codex
        let claudeProjects: URL
        let piAgent: URL
    }

    struct PiModels: Sendable {
        let custom: URL
        let store: URL
    }

    let logs: Logs
    let piModels: PiModels

    static var standard: UsageLocations {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let piAgent = home.appending(path: ".pi/agent", directoryHint: .isDirectory)
        return UsageLocations(
            logs: Logs(
                codex: Logs.Codex(
                    sessions: home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
                    archivedSessions: home.appending(
                        path: ".codex/archived_sessions",
                        directoryHint: .isDirectory
                    )
                ),
                claudeProjects: home.appending(
                    path: ".claude/projects",
                    directoryHint: .isDirectory
                ),
                piAgent: piAgent.appending(path: "sessions", directoryHint: .isDirectory)
            ),
            piModels: PiModels(
                custom: piAgent.appending(path: "models.json", directoryHint: .notDirectory),
                store: piAgent.appending(path: "models-store.json", directoryHint: .notDirectory)
            )
        )
    }
}

enum UsageEvent: Sendable {
    struct CodexID: Hashable, Sendable {
        let threadID: String
        let turnID: String?
        let ordinal: UInt64?
        let timestamp: Date
        let model: String
        let tokens: CodexTokenUsage
        let cumulativeTotal: Int64
    }

    struct ClaudeID: Hashable, Sendable {
        let messageID: String
        let requestID: String
    }

    struct ClaudeRevision: Sendable {
        let outputTokens: Int64
        let metadataCompleteness: Int
        let processedTokens: Int64
        let timestamp: Date

        fileprivate func isPreferred(over existing: Self) -> Bool {
            if outputTokens != existing.outputTokens {
                return outputTokens > existing.outputTokens
            }
            if metadataCompleteness != existing.metadataCompleteness {
                return metadataCompleteness > existing.metadataCompleteness
            }
            if processedTokens != existing.processedTokens {
                return processedTokens > existing.processedTokens
            }
            return timestamp > existing.timestamp
        }
    }

    enum ID: Hashable, Sendable {
        case codex(CodexID)
        case claude(ClaudeID)
        case piAgent(entryID: String, usage: UsageRecord)
    }

    case codex(id: CodexID, usage: UsageRecord)
    case claude(id: ClaudeID, usage: UsageRecord, revision: ClaudeRevision)
    case piAgent(entryID: String, usage: UsageRecord)

    var id: ID {
        switch self {
        case .codex(let id, _): .codex(id)
        case .claude(let id, _, _): .claude(id)
        case .piAgent(let entryID, let usage): .piAgent(entryID: entryID, usage: usage)
        }
    }

    var provider: UsageProvider {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .piAgent: .piAgent
        }
    }

    var usage: UsageRecord {
        switch self {
        case .codex(_, let usage), .claude(_, let usage, _), .piAgent(_, let usage): usage
        }
    }

    func isPreferred(over existing: Self) -> Bool {
        switch (self, existing) {
        case (.codex, .codex), (.piAgent, .piAgent):
            false
        case (
            .claude(_, _, let candidate),
            .claude(_, _, let existing)
        ):
            candidate.isPreferred(over: existing)
        case (.codex, .claude), (.codex, .piAgent), (.claude, .codex),
            (.claude, .piAgent), (.piAgent, .codex), (.piAgent, .claude):
            preconditionFailure("usage event id must identify one provider")
        }
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
