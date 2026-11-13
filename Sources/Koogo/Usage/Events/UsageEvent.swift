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
  init(timestamp: Date, processedTokens: UInt64, cost: Picodollars, model: ModelID?) {
    secondsSinceReferenceDate = timestamp.timeIntervalSinceReferenceDate
    self.processedTokens = processedTokens
    self.cost = cost
    self.model = model
  }

  let processedTokens: UInt64
  let cost: Picodollars
  /// absent when the log bills usage without a model, such as tool results or compaction.
  let model: ModelID?

  var timestamp: Date {
    Date(timeIntervalSinceReferenceDate: secondsSinceReferenceDate)
  }

  /// storing seconds avoids resilient date-layout value witnesses on every record copy.
  private let secondsSinceReferenceDate: TimeInterval
}

struct UsageEventID: Hashable, Comparable, Sendable {
  init(_ provider: Provider, fields: (inout Hasher) -> Void) {
    func digest(salt: UInt8) -> UInt64 {
      var hasher = Hasher()
      hasher.combine(salt)
      fields(&hasher)
      return UInt64(bitPattern: Int64(hasher.finalize()))
    }
    high = digest(salt: 0)
    low = UInt64(Provider.allCases.firstIndex(of: provider)!) << 56 | digest(salt: 1) >> 8
  }

  var provider: Provider {
    Provider.allCases[Int(low >> 56)]
  }

  static func <(lhs: Self, rhs: Self) -> Bool {
    (lhs.high, lhs.low) < (rhs.high, rhs.low)
  }

  private let high: UInt64
  private let low: UInt64
}

extension Hasher {
  /// identity fields hash their logged text; the length prefix keeps adjacent fields from trading bytes.
  mutating func combine(text: some Collection<UInt8>) {
    combine(text.count)
    if text.withContiguousStorageIfAvailable({ combine(bytes: UnsafeRawBufferPointer($0)) }) == nil {
      Array(text).withUnsafeBytes { combine(bytes: $0) }
    }
  }
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
