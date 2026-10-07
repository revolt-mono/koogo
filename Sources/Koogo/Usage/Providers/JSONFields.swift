import Foundation

struct JSONFieldKey {
    let name: StaticString
    /// A record whose member fails this test is of another kind, so the walk stops and every field reads as nil.
    let accepts: ((JSONValue) -> Bool)?
}

struct JSONField<Value> {
    let key: JSONFieldKey
    let decode: (JSONValue) throws -> Value?

    init(_ key: StaticString, accepts: ((JSONValue) -> Bool)? = nil, _ decode: @escaping (JSONValue) throws -> Value?) {
        self.key = JSONFieldKey(name: key, accepts: accepts)
        self.decode = decode
    }
}

extension JSONField where Value == JSONValue {
    static func value(_ key: StaticString) -> Self {
        Self(key) { $0 }
    }

    static func kind(_ key: StaticString, _ accepts: @escaping (JSONValue) -> Bool) -> Self {
        Self(key, accepts: accepts) { $0 }
    }
}

extension JSONField where Value == String {
    static func string(_ key: StaticString) -> Self {
        Self(key) { try $0.string() }
    }
}

extension JSONField where Value == UInt64 {
    static func uint64(_ key: StaticString) -> Self {
        Self(key) { try $0.integer() }
    }
}

extension JSONField where Value == Int64 {
    static func int64(_ key: StaticString) -> Self {
        Self(key) { try $0.integer() }
    }
}

extension JSONField where Value == Decimal {
    static func decimal(_ key: StaticString) -> Self {
        Self(key) { try $0.decimal() }
    }
}

// swiftlint:disable function_parameter_count large_tuple
extension JSONValue {
    /// Reads every field in one walk, the last occurrence of a key winning. Fixed arities stand in for a parameter pack because `.uint64("key")` does not infer against a pack element.
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

    func fields<A, B, C, D, E, F>(
        _ first: JSONField<A>,
        _ second: JSONField<B>,
        _ third: JSONField<C>,
        _ fourth: JSONField<D>,
        _ fifth: JSONField<E>,
        _ sixth: JSONField<F>
    ) throws -> (A?, B?, C?, D?, E?, F?) {
        let slots = try slots(for: [first.key, second.key, third.key, fourth.key, fifth.key, sixth.key])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode),
            try slots[3].flatMap(fourth.decode), try slots[4].flatMap(fifth.decode), try slots[5].flatMap(sixth.decode)
        )
    }

    func fields<A, B, C, D, E, F, G>(
        _ first: JSONField<A>,
        _ second: JSONField<B>,
        _ third: JSONField<C>,
        _ fourth: JSONField<D>,
        _ fifth: JSONField<E>,
        _ sixth: JSONField<F>,
        _ seventh: JSONField<G>
    ) throws -> (A?, B?, C?, D?, E?, F?, G?) {
        let slots = try slots(for: [first.key, second.key, third.key, fourth.key, fifth.key, sixth.key, seventh.key])
        return (
            try slots[0].flatMap(first.decode), try slots[1].flatMap(second.decode), try slots[2].flatMap(third.decode),
            try slots[3].flatMap(fourth.decode), try slots[4].flatMap(fifth.decode), try slots[5].flatMap(sixth.decode),
            try slots[6].flatMap(seventh.decode)
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
                if keys[index].accepts?(member.value) == false {
                    return InlineArray(repeating: nil)
                }
                slots[index] = member.value
                break
            }
        }
        return slots
    }
}
