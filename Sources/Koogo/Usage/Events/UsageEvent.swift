import Foundation

/// the logged model identifier, prefixed with `provider/model` for pi.
struct ModelID: RawRepresentable, Hashable, Comparable, Sendable, Encodable, ExpressibleByStringLiteral {
  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(stringLiteral value: String) {
    rawValue = value
  }

  let rawValue: String

  static func <(lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct UsageRecord: Sendable {
  let timestamp: UsageTimestamp
  let processedTokens: UInt64
  let cost: Picodollars
  /// absent when the log bills usage without a model, such as tool results or compaction.
  let model: ModelID?
}

struct UsageEvent: Sendable {
  init(id: UsageEventID, record: UsageRecord, revision: Revision = .none) {
    self.id = id
    self.record = record
    self.revision = revision
  }

  /// streamed output grows, while rewritten lines can add speed or cache metadata.
  struct Revision: Sendable {
    static let none = Self(outputTokens: 0, metadataCompleteness: 0)

    let outputTokens: UInt64
    let metadataCompleteness: UInt8
  }

  let id: UsageEventID
  let record: UsageRecord
  let revision: Revision

  var provider: Provider {
    id.provider
  }
}
