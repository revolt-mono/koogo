import Foundation

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

struct UsageEvent: Sendable {
    enum Key: Hashable, Sendable {
        /// A forked thread replays its parent's records under new thread ids, ordinals, and timestamps,
        /// so only the turn and its running total identify a request.
        case codex(turnID: String, cumulativeTotal: UInt64)
        case claude(messageID: String, requestID: String)
        case piAgent(entryID: String)
        /// Fork copies keep both fields, while a resumed Grok session can reuse an event id at a new time.
        case grok(eventID: String, timestamp: Date)
    }

    struct Revision: Comparable, Sendable {
        let outputTokens: UInt64
        let metadataCompleteness: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.outputTokens, lhs.metadataCompleteness) < (rhs.outputTokens, rhs.metadataCompleteness)
        }
    }

    struct Value: Sendable {
        let usage: UsageRecord
        let revision: Revision?

        func supersedes(_ existing: Self) -> Bool {
            guard let revision, let existingRevision = existing.revision else {
                return usage.timestamp < existing.usage.timestamp
            }
            return (revision, usage.processedTokens, usage.timestamp)
                > (existingRevision, existing.usage.processedTokens, existing.usage.timestamp)
        }
    }

    let key: Key
    let value: Value

    var usage: UsageRecord { value.usage }

    var provider: Provider {
        switch key {
        case .codex: .codex
        case .claude: .claude
        case .piAgent: .piAgent
        case .grok: .grok
        }
    }
}

extension UsageEvent {
    init(key: Key, usage: UsageRecord, revision: Revision? = nil) {
        self.init(key: key, value: Value(usage: usage, revision: revision))
    }
}
