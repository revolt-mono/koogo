/// contains a value for every key case, stored in case order; lookups are never optional.
struct EnumMap<Key: CaseIterable & Hashable, Value> where Key.AllCases == [Key] {
    private var values: [Value]

    init(_ make: (Key) throws -> Value) rethrows {
        values = try Key.allCases.map(make)
    }

    subscript(key: Key) -> Value {
        get { values[Self.slot(of: key)] }
        _modify { yield &values[Self.slot(of: key)] }
    }

    var entries: some Sequence<(key: Key, value: Value)> {
        zip(Key.allCases, values).lazy.map { (key: $0, value: $1) }
    }

    private static func slot(of key: Key) -> Int {
        Key.allCases.firstIndex(of: key)!
    }
}

extension EnumMap: Sendable where Key: Sendable, Value: Sendable {}

extension EnumMap: Equatable where Value: Equatable {}

extension EnumMap: Encodable where Key: Encodable & CodingKeyRepresentable, Value: Encodable {
    func encode(to encoder: Encoder) throws {
        try Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) }).encode(to: encoder)
    }
}
