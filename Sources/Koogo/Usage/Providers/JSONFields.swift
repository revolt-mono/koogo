import Foundation

struct JSONFieldKey {
    let name: StaticString
    let acceptsRecordKind: ((JSONValue) -> Bool)?
}

struct JSONField<Value> {
    let key: JSONFieldKey
    let decode: (JSONValue) throws -> Value?

    init(
        _ key: StaticString,
        acceptsRecordKind: ((JSONValue) -> Bool)? = nil,
        _ decode: @escaping (JSONValue) throws -> Value?
    ) {
        self.key = JSONFieldKey(name: key, acceptsRecordKind: acceptsRecordKind)
        self.decode = decode
    }
}

extension JSONField where Value == JSONValue {
    static func value(_ key: StaticString) -> Self {
        Self(key) { $0 }
    }

    static func kind(_ key: StaticString, _ acceptsRecordKind: @escaping (JSONValue) -> Bool) -> Self {
        Self(key, acceptsRecordKind: acceptsRecordKind) { $0 }
    }
}

extension JSONField where Value == String {
    static func string(_ key: StaticString) -> Self {
        Self(key) { try $0.string() }
    }
}

extension JSONField where Value == UInt64 {
    static func uint64(_ key: StaticString) -> Self {
        Self(key) { try $0.uint64() }
    }
}

extension JSONField where Value == Picodollars {
    static func usd(_ key: StaticString) -> Self {
        Self(key) { try $0.usd() }
    }
}

// swiftlint:disable function_parameter_count large_tuple
extension JSONValue {
    /// reads fields in one scan; the last duplicate key wins. fixed arities avoid parameter-pack inference limits.
    func fields<A>(_ first: JSONField<A>) throws -> A? {
        let slots = try slots(for: [first.key])
        return try slots[0].flatMap(first.decode)
    }

    func fields<A, B>(_ first: JSONField<A>, _ second: JSONField<B>) throws -> (A?, B?) {
        let slots = try slots(for: [first.key, second.key])
        return (try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode))
    }

    func fields<A, B, C>(_ first: JSONField<A>, _ second: JSONField<B>, _ third: JSONField<C>) throws -> (A?, B?, C?) {
        let slots = try slots(for: [first.key, second.key, third.key])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode)
        )
    }

    func fields<A, B, C, D>(
        _ first: JSONField<A>,
        _ second: JSONField<B>,
        _ third: JSONField<C>,
        _ fourth: JSONField<D>
    ) throws -> (A?, B?, C?, D?) {
        let slots = try slots(for: [first.key, second.key, third.key, fourth.key])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode),
            try slots[3].flatMap(fourth.decode)
        )
    }

    func fields<A, B, C, D, E>(
        _ first: JSONField<A>,
        _ second: JSONField<B>,
        _ third: JSONField<C>,
        _ fourth: JSONField<D>,
        _ fifth: JSONField<E>
    ) throws -> (A?, B?, C?, D?, E?) {
        let slots = try slots(for: [first.key, second.key, third.key, fourth.key, fifth.key])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode),
            try slots[3].flatMap(fourth.decode), try slots[4].flatMap(fifth.decode)
        )
    }

    func fields<A, B, C, D, E, F, G, H>(
        _ first: JSONField<A>,
        _ second: JSONField<B>,
        _ third: JSONField<C>,
        _ fourth: JSONField<D>,
        _ fifth: JSONField<E>,
        _ sixth: JSONField<F>,
        _ seventh: JSONField<G>,
        _ eighth: JSONField<H>
    ) throws -> (A?, B?, C?, D?, E?, F?, G?, H?) {
        let slots = try slots(for: [
            first.key, second.key, third.key, fourth.key, fifth.key, sixth.key, seventh.key, eighth.key,
        ])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode),
            try slots[3].flatMap(fourth.decode), try slots[4].flatMap(fifth.decode), try slots[5].flatMap(sixth.decode),
            try slots[6].flatMap(seventh.decode), try slots[7].flatMap(eighth.decode)
        )
    }

    // swiftlint:enable function_parameter_count large_tuple

    private func slots<let count: Int>(for keys: InlineArray<count, JSONFieldKey>) throws -> InlineArray<count, Self?> {
        var object = try object()
        var slots = InlineArray<count, Self?>(repeating: nil)
        while let member = try object.next() {
            for index in keys.indices where member.key.isString(keys[index].name) {
                if keys[index].acceptsRecordKind?(member.value) == false {
                    return InlineArray(repeating: nil)
                }
                slots[index] = member.value
                break
            }
        }
        return slots
    }
}
