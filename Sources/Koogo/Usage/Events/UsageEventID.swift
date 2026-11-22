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
  /// the length prefix keeps adjacent fields from trading bytes.
  mutating func combine(text: some Collection<UInt8>) {
    combine(text.count)
    if text.withContiguousStorageIfAvailable({ combine(bytes: UnsafeRawBufferPointer($0)) }) == nil {
      Array(text).withUnsafeBytes { combine(bytes: $0) }
    }
  }
}
