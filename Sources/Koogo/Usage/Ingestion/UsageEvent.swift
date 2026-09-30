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
    struct Key: Hashable, Sendable {
        let provider: Provider
        private let id: String
        private let ordinal: UInt64

        /// A forked thread replays its parent's records under new thread ids, ordinals, and timestamps,
        /// so only the turn and its running total identify a request.
        static func codex(turnID: String, cumulativeTotal: UInt64) -> Self {
            Self(provider: .codex, id: turnID, ordinal: cumulativeTotal)
        }

        static func claude(messageID: String, requestID: String) -> Self {
            Self(provider: .claude, id: "\(messageID.utf8.count):\(messageID)\(requestID)", ordinal: 0)
        }

        static func piAgent(entryID: String) -> Self {
            Self(provider: .piAgent, id: entryID, ordinal: 0)
        }

        /// Fork copies keep both fields, while a resumed Grok session can reuse an event id at a new time.
        static func grok(eventID: String, timestamp: Date) -> Self {
            Self(provider: .grok, id: eventID, ordinal: timestamp.timeIntervalSinceReferenceDate.bitPattern)
        }
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

    var provider: Provider { key.provider }
}

extension UsageEvent {
    init(key: Key, usage: UsageRecord, revision: Revision? = nil) {
        self.init(key: key, value: Value(usage: usage, revision: revision))
    }
}
