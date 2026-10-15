/// contains a value for every key case; lookups are never optional.
struct EnumMap<Key: CaseIterable & Hashable, Value> {
    private let keys: [Key]
    private var values: [Value]

    init(_ make: (Key) throws -> Value) rethrows {
        keys = Array(Key.allCases)
        values = try keys.map(make)
    }

    subscript(key: Key) -> Value {
        get { values[slot(of: key)] }
        _modify { yield &values[slot(of: key)] }
    }

    var entries: some Sequence<(key: Key, value: Value)> {
        zip(keys, values).lazy.map { (key: $0, value: $1) }
    }

    private func slot(of key: Key) -> Int {
        keys.firstIndex(of: key)!
    }
}

extension EnumMap: Sendable where Key: Sendable, Value: Sendable {}

extension EnumMap: Equatable where Value: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.values == rhs.values
    }
}

extension EnumMap: Encodable where Key: Encodable & CodingKeyRepresentable, Value: Encodable {
    func encode(to encoder: Encoder) throws {
        try Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) }).encode(to: encoder)
    }
}
