import Foundation

enum UsageProvider: String, CaseIterable, Sendable {
    case codex
    case claude
}

enum UsagePeriod: String, CaseIterable, Sendable {
    case today
    case week
    case month
}

struct UsagePeriodSnapshot: Equatable, Sendable {
    let processedTokens: Int64
    let costUSD: Decimal
    let favoriteModel: String?
    let favoriteReasoningEffort: String?

    static let zero = UsagePeriodSnapshot(
        processedTokens: 0,
        costUSD: 0,
        favoriteModel: nil,
        favoriteReasoningEffort: nil
    )
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    let today: UsagePeriodSnapshot
    let week: UsagePeriodSnapshot
    let month: UsagePeriodSnapshot

    static let zero = ProviderUsageSnapshot(today: .zero, week: .zero, month: .zero)

    subscript(period: UsagePeriod) -> UsagePeriodSnapshot {
        switch period {
        case .today: today
        case .week: week
        case .month: month
        }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let codex: ProviderUsageSnapshot
    let claude: ProviderUsageSnapshot

    subscript(provider: UsageProvider) -> ProviderUsageSnapshot {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
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
    let uncachedInput: Int64
    let cachedInput: Int64
    let cacheWrite5MinuteInput: Int64
    let cacheWrite1HourInput: Int64
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
        enum ServiceTier: Sendable {
            case standard
            case fast
            case flex
        }

        let threadID: String
        let turnID: String?
        let ordinal: UInt64?
        let details: Details
        let reasoningOutput: Int64
        let cumulativeTotal: Int64
        let serviceTier: ServiceTier
    }

    struct Claude: Sendable {
        enum Speed: Sendable {
            case standard
            case fast
        }

        let messageID: String
        let requestID: String
        let details: Details
        let speed: Speed
        let inferenceGeo: String?
        let webSearchRequests: Int64
        let hasExplicitSpeed: Bool
        let hasExplicitCacheDuration: Bool
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

    var provider: UsageProvider {
        switch self {
        case .codex: .codex
        case .claude: .claude
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

        let candidateMetadata = (candidate.hasExplicitSpeed ? 1 : 0)
            + (candidate.hasExplicitCacheDuration ? 1 : 0)
            + (candidate.details.reasoningEffort == nil ? 0 : 1)
        let existingMetadata = (existing.hasExplicitSpeed ? 1 : 0)
            + (existing.hasExplicitCacheDuration ? 1 : 0)
            + (existing.details.reasoningEffort == nil ? 0 : 1)
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
    let today: Date
    let week: Date
    let month: Date

    var earliestStart: Date {
        min(today, min(week, month))
    }

    subscript(period: UsagePeriod) -> Date {
        switch period {
        case .today: today
        case .week: week
        case .month: month
        }
    }

    static func containing(_ date: Date, calendar: Calendar) -> UsagePeriodIntervals? {
        guard
            let today = calendar.dateInterval(of: .day, for: date)?.start,
            let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
            let month = calendar.dateInterval(of: .month, for: date)?.start
        else {
            return nil
        }

        return UsagePeriodIntervals(today: today, week: week, month: month)
    }
}

func parseUsageTimestamp(_ value: String) -> Date? {
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
    }
    return try? Date.ISO8601FormatStyle().parse(value)
}
