import Foundation

/// One provider's line-oriented log format. Parsers carry per-file state such as
/// the current Codex turn, so each tracked file owns its own instance.
protocol UsageLogParser: Sendable {
    /// Returns `nil` for a line that bills nothing, and throws for a line of a record kind the
    /// parser knows whose fields it cannot use. Parsers rule out what they can from a line's bytes
    /// before paying for a JSON decode.
    mutating func parse(_ line: UnsafeRawBufferPointer, decoder: inout UsageLineDecoder) throws -> UsageLineOutcome?
}

/// A known record kind with missing or invalid fields, thrown by parsers after decoding succeeds.
struct MalformedUsageRecord: Error {}

/// Decodes log lines in place and counts them. Decoding dominates ingestion, so the count, reported per
/// provider, is what shows a prefilter that stopped matching its provider's format.
struct UsageLineDecoder {
    private let decoder = JSONDecoder()
    private(set) var decodedLines = 0

    mutating func decode<T: Decodable>(_ type: T.Type, from line: UnsafeRawBufferPointer) throws -> T {
        decodedLines += 1
        guard let baseAddress = line.baseAddress else {
            return try decoder.decode(type, from: Data())
        }
        let data = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: baseAddress),
            count: line.count,
            deallocator: .none
        )
        return try decoder.decode(type, from: data)
    }
}

func parseUsageTimestamp(_ value: String) -> Date? {
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
        return date
    }
    return try? Date.ISO8601FormatStyle().parse(value)
}

protocol LogRecordKind: RawRepresentable, Decodable, Sendable where RawValue == String {
    static var other: Self { get }
}

extension LogRecordKind {
    /// The kind named `rawValue`, or `.other` for a kind the parser does not know.
    init(known rawValue: String) {
        self = Self(rawValue: rawValue) ?? .other
    }

    init(from decoder: Decoder) throws {
        self.init(known: try decoder.singleValueContainer().decode(String.self))
    }

    var jsonStringMarker: Data {
        Data("\"\(rawValue)\"".utf8)
    }
}

extension UnsafeRawBufferPointer {
    func contains(_ marker: Data) -> Bool {
        guard let baseAddress else {
            return false
        }
        return marker.withUnsafeBytes { memmem(baseAddress, count, $0.baseAddress, $0.count) != nil }
    }
}

/// A forward-only reader over the members at the front of a compact, single-line JSON object, so a parser can
/// tell what a record is from its leading fields without scanning the rest of a long line. It steps over string,
/// number, boolean, and null values but stops at objects, arrays, whitespace, and escapes. A `nil` answer only
/// means the reader stopped before finding the member; callers then fall back to a full scan or decode, so the
/// reader must be right only when it answers.
struct JSONLeadingMembers {
    private let bytes: UnsafeRawBufferPointer
    /// The start of the next member's key; nil once the reader has stopped.
    private var offset: Int?

    init(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
        offset = bytes.first == UInt8(ascii: "{") ? 1 : nil
    }

    /// Steps to the member named `key` and returns its value when that is a string without escapes.
    mutating func string(_ key: String) -> String? {
        guard let valueStart = seek(key), let end = stringEnd(at: valueStart) else {
            offset = nil
            return nil
        }
        offset = memberEnd(after: end)
        let value = UnsafeRawBufferPointer(rebasing: bytes[valueStart + 1..<end - 1])
        // Much cheaper than `String(validating:)` on this hot path; invalid UTF-8 comes back repaired.
        return String(unsafeUninitializedCapacity: value.count) { $0.initialize(fromContentsOf: value) }
    }

    /// Steps to the member named `key` and returns a reader over its value when that is an object;
    /// this reader stops there.
    mutating func object(_ key: String) -> Self? {
        defer { offset = nil }
        guard let valueStart = seek(key), bytes[valueStart] == UInt8(ascii: "{") else {
            return nil
        }
        return Self(UnsafeRawBufferPointer(rebasing: bytes[valueStart...]))
    }

    /// The offset of the value of the next member named `key`, stepping over scalar members before it.
    private mutating func seek(_ key: String) -> Int? {
        while let keyStart = offset, let keyEnd = stringEnd(at: keyStart), keyEnd < bytes.count,
            bytes[keyEnd] == UInt8(ascii: ":"), keyEnd + 1 < bytes.count
        {
            let valueStart = keyEnd + 1
            if bytes[keyStart + 1..<keyEnd - 1].elementsEqual(key.utf8) {
                return valueStart
            }
            offset = scalarEnd(at: valueStart).flatMap(memberEnd(after:))
        }
        return nil
    }

    /// The offset just past the string starting at `start`, when it has no escapes.
    private func stringEnd(at start: Int) -> Int? {
        guard start < bytes.count, bytes[start] == UInt8(ascii: "\""), let base = bytes.baseAddress else {
            return nil
        }
        let contentStart = base + start + 1
        guard let quote = memchr(contentStart, Int32(UInt8(ascii: "\"")), bytes.count - start - 1),
            memchr(contentStart, Int32(UInt8(ascii: "\\")), contentStart.distance(to: quote)) == nil
        else {
            return nil
        }
        return base.distance(to: quote) + 1
    }

    /// The offset just past the string, number, boolean, or null starting at `start`; nil for an object or array.
    private func scalarEnd(at start: Int) -> Int? {
        switch bytes[start] {
        case UInt8(ascii: "\""):
            stringEnd(at: start)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            nil
        default:
            bytes[start...].firstIndex { $0 == UInt8(ascii: ",") || $0 == UInt8(ascii: "}") }
        }
    }

    /// The start of the next member after a value ending at `end`; nil at the end of the object.
    private func memberEnd(after end: Int) -> Int? {
        end + 1 < bytes.count && bytes[end] == UInt8(ascii: ",") ? end + 1 : nil
    }
}
