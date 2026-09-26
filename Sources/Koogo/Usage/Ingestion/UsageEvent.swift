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

/// One billed request. Copies of it in other files or rereads share its key.
struct UsageEvent: Sendable {
    enum Key: Hashable, Sendable {
        case codex(threadID: String, turnID: String?, ordinal: UInt64?, timestamp: Date, cumulativeTotal: UInt64)
        case claude(messageID: String, requestID: String)
        case piAgent(entryID: String)
        /// Fork copies keep both fields, while a resumed Grok session can reuse an event id at a new time.
        case grok(eventID: String, timestamp: Date)
    }

    /// How complete a copy is, for providers that log partial copies of one request.
    struct Revision: Comparable, Sendable {
        let outputTokens: UInt64
        let metadataCompleteness: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.outputTokens, lhs.metadataCompleteness) < (rhs.outputTokens, rhs.metadataCompleteness)
        }
    }

    let key: Key
    let usage: UsageRecord
    let revision: Revision?

    init(key: Key, usage: UsageRecord, revision: Revision? = nil) {
        self.key = key
        self.usage = usage
        self.revision = revision
    }

    var provider: UsageProvider {
        switch key {
        case .codex: .codex
        case .claude: .claude
        case .piAgent: .piAgent
        case .grok: .grok
        }
    }

    /// Whether this copy replaces `existing` under the same key. Unless both copies carry a
    /// revision, the first copy wins.
    func supersedes(_ existing: UsageEvent) -> Bool {
        guard let revision, let existingRevision = existing.revision else {
            return false
        }
        return (revision, usage.processedTokens, usage.timestamp)
            > (existingRevision, existing.usage.processedTokens, existing.usage.timestamp)
    }
}
