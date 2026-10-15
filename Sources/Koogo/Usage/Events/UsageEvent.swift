import Foundation

/// the logged model identifier, prefixed with `provider/model` for pi.
struct ModelID: Hashable, Comparable, Sendable, Encodable, ExpressibleByStringLiteral {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct UsageRecord: Sendable {
    /// storing seconds avoids resilient date-layout value witnesses on every record copy.
    private let secondsSinceReferenceDate: TimeInterval
    let processedTokens: UInt64
    let cost: Picodollars
    /// absent when the log bills usage without a model, such as tool results or compaction.
    let model: ModelID?

    var timestamp: Date {
        Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
    }

    init(timestamp: Date, processedTokens: UInt64, cost: Picodollars, model: ModelID?) {
        secondsSinceReferenceDate = timestamp.timeIntervalSinceReferenceDate
        self.processedTokens = processedTokens
        self.cost = cost
        self.model = model
    }
}

struct UsageEventID: Hashable, Comparable, Sendable {
    private let high: UInt64
    private let low: UInt64
    let provider: Provider

    private init(_ provider: Provider, fields: (inout Hasher) -> Void) {
        func digest(salt: UInt8) -> UInt64 {
            var hasher = Hasher()
            hasher.combine(salt)
            fields(&hasher)
            return UInt64(bitPattern: Int64(hasher.finalize()))
        }
        high = digest(salt: 0)
        low = digest(salt: 1)
        self.provider = provider
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.high, lhs.low, lhs.provider.rawValue) < (rhs.high, rhs.low, rhs.provider.rawValue)
    }

    /// codex forks change thread ids, ordinals, and timestamps; turn id and cumulative total remain stable.
    static func codex(turnID: String, cumulativeTotal: UInt64) -> Self {
        Self(.codex) {
            $0.combine(turnID)
            $0.combine(cumulativeTotal)
        }
    }

    static func claude(messageID: String, requestID: String) -> Self {
        Self(.claude) {
            $0.combine(messageID)
            $0.combine(requestID)
        }
    }

    static func piAgent(entryID: String) -> Self {
        Self(.piAgent) { $0.combine(entryID) }
    }

    /// grok forks preserve both fields; resumed sessions can reuse an event id at a later time.
    static func grok(eventID: String, timestampMilliseconds: UInt64) -> Self {
        Self(.grok) {
            $0.combine(eventID)
            $0.combine(timestampMilliseconds)
        }
    }
}

struct UsageEvent: Sendable {
    /// streamed output grows, while rewritten lines can add speed or cache metadata.
    struct Revision: Comparable, Sendable {
        let outputTokens: UInt64
        let metadataCompleteness: UInt8

        static let none = Self(outputTokens: 0, metadataCompleteness: 0)

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.outputTokens, lhs.metadataCompleteness) < (rhs.outputTokens, rhs.metadataCompleteness)
        }
    }

    let id: UsageEventID
    let record: UsageRecord
    let revision: Revision

    init(id: UsageEventID, record: UsageRecord, revision: Revision = .none) {
        self.id = id
        self.record = record
        self.revision = revision
    }

    var provider: Provider { id.provider }
}
