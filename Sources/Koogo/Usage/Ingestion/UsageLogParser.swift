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

private let logTypeKey = Data("\"type\"".utf8)

protocol LogRecordKind: RawRepresentable, Decodable, Sendable where RawValue == String {
    static var other: Self { get }
}

extension LogRecordKind {
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }

    var jsonStringMarker: Data {
        Data(("\"" + rawValue + "\"").utf8)
    }
}

extension UnsafeRawBufferPointer {
    func containsTypeValue(in values: [Data]) -> Bool {
        guard let baseAddress else {
            return false
        }
        let bytes = bindMemory(to: UInt8.self)
        var searchStart = 0

        while searchStart < count {
            let match = logTypeKey.withUnsafeBytes { key in
                memmem(
                    baseAddress.advanced(by: searchStart),
                    count - searchStart,
                    key.baseAddress,
                    key.count
                )
            }
            guard let match else {
                return false
            }

            var valueStart =
                baseAddress.distance(to: UnsafeRawPointer(match))
                + logTypeKey.count
            while valueStart < count, bytes[valueStart].isJSONWhitespace {
                valueStart += 1
            }
            guard valueStart < count, bytes[valueStart] == 0x3A else {
                searchStart = valueStart
                continue
            }
            valueStart += 1
            while valueStart < count, bytes[valueStart].isJSONWhitespace {
                valueStart += 1
            }
            for value in values where matches(value, at: valueStart) {
                return true
            }
            searchStart = valueStart
        }
        return false
    }

    private func matches(_ data: Data, at index: Int) -> Bool {
        guard let baseAddress, index <= count, count - index >= data.count else {
            return false
        }
        return data.withUnsafeBytes { candidate in
            guard let candidateAddress = candidate.baseAddress else {
                return false
            }
            return memcmp(baseAddress.advanced(by: index), candidateAddress, candidate.count) == 0
        }
    }
}

extension UInt8 {
    fileprivate var isJSONWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
