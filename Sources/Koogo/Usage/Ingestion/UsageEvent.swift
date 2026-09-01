import Foundation

/// What parsing one log line produced; drops are first-class so they share
/// the event index's history-window retention instead of accumulating forever.
enum UsageLineOutcome: Sendable {
    case event(UsageEvent)
    case unpricedModel(id: String, timestamp: Date)

    var timestamp: Date {
        switch self {
        case .event(let event): event.usage.timestamp
        case .unpricedModel(_, let timestamp): timestamp
        }
    }
}

enum UsageEvent: Sendable {
    struct CodexID: Hashable, Sendable {
        let threadID: String
        let turnID: String?
        let ordinal: UInt64?
        let timestamp: Date
        let cumulativeTotal: UInt64
    }

    struct ClaudeID: Hashable, Sendable {
        let messageID: String
        let requestID: String
    }

    struct ClaudeRevision: Sendable {
        let outputTokens: UInt64
        let metadataCompleteness: Int
        let processedTokens: UInt64
        let timestamp: Date

        func isPreferred(over existing: Self) -> Bool {
            (outputTokens, metadataCompleteness, processedTokens, timestamp)
                > (
                    existing.outputTokens,
                    existing.metadataCompleteness,
                    existing.processedTokens,
                    existing.timestamp
                )
        }
    }

    case codex(id: CodexID, usage: UsageRecord)
    case claude(id: ClaudeID, usage: UsageRecord, revision: ClaudeRevision)
    case piAgent(entryID: String, usage: UsageRecord)

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
}
