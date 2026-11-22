struct EnumMap<Key: CaseIterable & Hashable, Value> where Key.AllCases == [Key] {
  init(_ make: (Key) throws -> Value) rethrows {
    values = try Key.allCases.map(make)
  }

  private(set) var values: [Value]

  var entries: some Sequence<(key: Key, value: Value)> {
    zip(Key.allCases, values).lazy.map { (key: $0, value: $1) }
  }

  subscript(key: Key) -> Value {
    get { values[Self.slot(of: key)] }
    _modify { yield &values[Self.slot(of: key)] }
  }

  private static func slot(of key: Key) -> Int {
    Key.allCases.firstIndex(of: key)!
  }
}

extension EnumMap: Sendable where Key: Sendable, Value: Sendable { }

extension EnumMap: Equatable where Value: Equatable { }

extension EnumMap: Encodable where Key: Encodable & CodingKeyRepresentable, Value: Encodable {
  func encode(to encoder: any Encoder) throws {
    try Dictionary(uniqueKeysWithValues: zip(Key.allCases, values)).encode(to: encoder)
  }
}
