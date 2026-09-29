import Foundation

/// A forward-only reader over one JSON object's members. It finds each value's extent by scanning bytes, without
/// validating what it steps over, so a parser reads only the fields it bills from and a long log line costs little
/// more than a scan for its quotes.
struct JSONObjectReader {
    struct Member {
        let key: JSONValue
        let value: JSONValue
    }

    private let bytes: UnsafeRawBufferPointer
    private var offset: Int
    private var hasMember = false

    /// Nil unless `bytes` holds an object, allowing surrounding whitespace.
    init?(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
        offset = 0
        skipWhitespace()
        guard offset < bytes.count, bytes[offset] == UInt8(ascii: "{") else {
            return nil
        }
        offset += 1
    }

    /// The next member, or nil at the closing brace. Throws when the object is cut short or misshapen.
    mutating func next() throws -> Member? {
        skipWhitespace()
        guard offset < bytes.count else {
            throw MalformedUsageRecord()
        }
        switch bytes[offset] {
        case UInt8(ascii: "}"):
            // Only whitespace may follow, so a line with trailing data is not billed as a record.
            guard bytes[(offset + 1)...].allSatisfy(Self.isWhitespace) else {
                throw MalformedUsageRecord()
            }
            return nil
        case UInt8(ascii: ",") where hasMember:
            offset += 1
            skipWhitespace()
        default:
            guard !hasMember else {
                throw MalformedUsageRecord()
            }
        }
        let keyStart = offset
        offset = try stringEnd(at: keyStart)
        let key = JSONValue(bytes: UnsafeRawBufferPointer(rebasing: bytes[keyStart..<offset]))
        skipWhitespace()
        guard offset < bytes.count, bytes[offset] == UInt8(ascii: ":") else {
            throw MalformedUsageRecord()
        }
        offset += 1
        skipWhitespace()
        let valueStart = offset
        offset = try valueEnd(at: valueStart)
        hasMember = true
        return Member(key: key, value: JSONValue(bytes: UnsafeRawBufferPointer(rebasing: bytes[valueStart..<offset])))
    }

    private mutating func skipWhitespace() {
        while offset < bytes.count, Self.isWhitespace(bytes[offset]) {
            offset += 1
        }
    }

    /// The offset just past the value starting at `start`.
    private func valueEnd(at start: Int) throws -> Int {
        guard start < bytes.count else {
            throw MalformedUsageRecord()
        }
        switch bytes[start] {
        case UInt8(ascii: "\""):
            return try stringEnd(at: start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var index = start
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    index = try stringEnd(at: index)
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 {
                        return index + 1
                    }
                default:
                    break
                }
                index += 1
            }
            throw MalformedUsageRecord()
        default:
            var index = start
            while index < bytes.count, !Self.endsScalar(bytes[index]) {
                index += 1
            }
            guard index > start else {
                throw MalformedUsageRecord()
            }
            return index
        }
    }

    /// The offset just past the string starting at `start`.
    private func stringEnd(at start: Int) throws -> Int {
        guard start < bytes.count, bytes[start] == UInt8(ascii: "\""), let base = bytes.baseAddress else {
            throw MalformedUsageRecord()
        }
        var searchStart = start + 1
        while let quote = memchr(base + searchStart, Int32(UInt8(ascii: "\"")), bytes.count - searchStart) {
            let quoteIndex = base.distance(to: quote)
            var backslashes = 0
            while bytes[quoteIndex - 1 - backslashes] == UInt8(ascii: "\\") {
                backslashes += 1
            }
            if backslashes.isMultiple(of: 2) {
                return quoteIndex + 1
            }
            searchStart = quoteIndex + 1
        }
        throw MalformedUsageRecord()
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t")
            || byte == UInt8(ascii: "\r")
    }

    private static func endsScalar(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") || isWhitespace(byte)
    }
}

/// The bytes of one JSON value, read on demand.
struct JSONValue {
    let bytes: UnsafeRawBufferPointer

    /// Matches a string whose content is `literal`, as in `case "type":`.
    static func ~= (literal: StaticString, value: Self) -> Bool {
        value.isString(literal)
    }

    var isNull: Bool {
        bytes.elementsEqual("null".utf8)
    }

    /// Matches known field names and record kinds, whose literals need no JSON escaping.
    func isString(_ literal: StaticString) -> Bool {
        guard let content = unescapedString else {
            return bytes.first == UInt8(ascii: "\"") && (try? string()) == literal.description
        }
        return content.count == literal.utf8CodeUnitCount
            && memcmp(content.baseAddress, literal.utf8Start, literal.utf8CodeUnitCount) == 0
    }

    /// The string this value holds, or nil for null.
    func string() throws -> String? {
        if isNull {
            return nil
        }
        if let raw = unescapedString, !raw.contains(where: { $0 < 0x20 }) {
            guard let string = String(validating: raw, as: UTF8.self) else {
                throw MalformedUsageRecord()
            }
            return string
        }
        // Escapes are rare enough to leave to Foundation, which also rejects control characters.
        return try JSONDecoder().decode(String.self, from: Data(bytes))
    }

    /// Nil for null, so an optional member reads like an absent one.
    var nonNull: Self? {
        isNull ? nil : self
    }

    /// The integer this value holds, or nil for null. Throws for a fraction or a value outside `T`.
    func integer<T: FixedWidthInteger & Decodable>(_: T.Type = T.self) throws -> T? {
        guard !isNull else {
            return nil
        }
        // Plain digits are read here; signs, leading zeros, fractions, exponents, and overflow are rare
        // enough to leave to Foundation.
        guard bytes.first != UInt8(ascii: "0") || bytes.count == 1 else {
            return try JSONDecoder().decode(T.self, from: Data(bytes))
        }
        var value: T = 0
        for byte in bytes {
            let (tens, overflow) = value.multipliedReportingOverflow(by: 10)
            let (next, carry) = tens.addingReportingOverflow(T(truncatingIfNeeded: byte &- UInt8(ascii: "0")))
            guard Self.isDigit(byte), !overflow, !carry else {
                return try JSONDecoder().decode(T.self, from: Data(bytes))
            }
            value = next
        }
        return value
    }

    /// The number this value holds, exactly as written, or nil for null.
    func decimal() throws -> Decimal? {
        guard !isNull else {
            return nil
        }
        guard isNumber, let text = String(bytes: bytes, encoding: .ascii), let value = Decimal(string: text) else {
            throw MalformedUsageRecord()
        }
        return value
    }

    /// The members of the object this value holds.
    func object() throws -> JSONObjectReader {
        guard let object = JSONObjectReader(bytes) else {
            throw MalformedUsageRecord()
        }
        return object
    }

    /// The value of the member named `key` in the object this value holds, or nil when it has none.
    func member(_ key: StaticString) throws -> Self? {
        var object = try object()
        var value: Self?
        // Reads to the closing brace, so the rest of the object is checked too.
        while let member = try object.next() {
            if member.key.isString(key) {
                value = member.value
            }
        }
        return value
    }

    /// Whether the bytes spell a JSON number; `Decimal(string:)` alone would accept trailing text.
    private var isNumber: Bool {
        var index = 0
        func skipDigits() -> Bool {
            let start = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
            }
            return index > start
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
            index += 1
        }
        // JSON allows no leading zeros.
        if index < bytes.count, bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else if !skipDigits() {
            return false
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard skipDigits() else {
                return false
            }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard skipDigits() else {
                return false
            }
        }
        return index == bytes.count
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// The content of a string without escapes; nil for anything else.
    private var unescapedString: UnsafeRawBufferPointer? {
        guard bytes.count >= 2, bytes.first == UInt8(ascii: "\""), let base = bytes.baseAddress,
            memchr(base + 1, Int32(UInt8(ascii: "\\")), bytes.count - 2) == nil
        else {
            return nil
        }
        return UnsafeRawBufferPointer(rebasing: bytes[1..<bytes.count - 1])
    }
}
