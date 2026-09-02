import Foundation

/// One provider's line-oriented log format. Parsers carry per-file state such as
/// the current Codex turn, so each tracked file owns its own instance.
protocol UsageLogParser: Sendable {
    /// Cheap byte-level prefilter that runs before any JSON decoding.
    func mayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool
    mutating func parse(_ line: Data, decoder: JSONDecoder) -> UsageLineOutcome?
}

extension UsageLogParser {
    func mayContainEvent(_: UnsafeRawBufferPointer) -> Bool {
        true
    }

    mutating func parse(_ line: UnsafeRawBufferPointer, decoder: JSONDecoder) -> UsageLineOutcome? {
        guard mayContainEvent(line), let baseAddress = line.baseAddress else {
            return nil
        }
        let data = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: baseAddress),
            count: line.count,
            deallocator: .none
        )
        return parse(data, decoder: decoder)
    }
}

extension UsageProvider {
    func makeLogParser() -> any UsageLogParser {
        switch self {
        case .codex: CodexLogParser()
        case .claude: ClaudeLogParser()
        case .piAgent: PiLogParser()
        }
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
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
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
