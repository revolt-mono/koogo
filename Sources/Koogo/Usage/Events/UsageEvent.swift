import Foundation

/// A provider's model identifier as logged, or for Pi `provider/model`.
struct ModelID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct UsageRecord: Sendable {
    struct ModelTurn: Sendable {
        let model: ModelID
        let reasoningEffort: String?
    }

    /// Held as seconds because `Date` has a resilient layout, which routes every copy of a record
    /// through runtime value witnesses.
    private let secondsSinceReferenceDate: TimeInterval
    let processedTokens: UInt64
    let costUSD: Decimal
    let modelTurn: ModelTurn?

    var timestamp: Date {
        Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
    }

    init(timestamp: Date, processedTokens: UInt64, costUSD: Decimal, modelTurn: ModelTurn?) {
        secondsSinceReferenceDate = timestamp.timeIntervalSinceReferenceDate
        self.processedTokens = processedTokens
        self.costUSD = costUSD
        self.modelTurn = modelTurn
    }
}

/// What identifies one billed request across log copies. Each provider has one rule.
enum UsageEventID: Hashable, Sendable {
    /// A forked thread replays its parent's records under new thread ids, ordinals, and timestamps,
    /// so only the turn and its running total identify a request.
    case codex(turnID: String, cumulativeTotal: UInt64)
    case claude(messageID: String, requestID: String)
    case piAgent(entryID: String)
    /// Fork copies keep both fields, while a resumed Grok session can reuse an event id at a new time.
    case grok(eventID: String, timestampMilliseconds: UInt64)

    var provider: Provider {
        switch self {
        case .codex: .codex
        case .claude: .claude
        case .piAgent: .piAgent
        case .grok: .grok
        }
    }
}

struct UsageEvent: Sendable {
    /// How complete one copy of a request is. A streamed reply grows its output, and a rewritten line
    /// can add metadata such as speed, cache split, or reasoning effort.
    struct Revision: Comparable, Sendable {
        let outputTokens: UInt64
        let metadataCompleteness: Int

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

    /// The more complete copy wins; identical copies keep the one logged first.
    func supersedes(record existing: UsageRecord, revision existingRevision: Revision) -> Bool {
        let rank = (revision, record.processedTokens)
        let existingRank = (existingRevision, existing.processedTokens)
        return rank == existingRank ? record.timestamp < existing.timestamp : rank > existingRank
    }
}
