import Foundation

private protocol LogRecordKind: RawRepresentable, Decodable, Sendable where RawValue == String {
    static var other: Self { get }
}

private extension LogRecordKind {
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }

    var jsonStringMarker: Data {
        Data(("\"" + rawValue + "\"").utf8)
    }
}

private enum CodexRecordKind: String, LogRecordKind {
    case sessionMeta = "session_meta"
    case turnContext = "turn_context"
    case eventMessage = "event_msg"
    case other
}

private enum CodexPayloadKind: String, LogRecordKind {
    case tokenCount = "token_count"
    case other
}

private enum ClaudeRecordKind: String, LogRecordKind {
    case assistant
    case other
}

enum UsageFileParserState: Sendable {
    case codex(CodexLogParser = CodexLogParser())
    case claude

    mutating func parse(
        _ line: UnsafeRawBufferPointer,
        source: String,
        decoder: JSONDecoder
    ) -> UsageEvent? {
        let containsMarker = switch self {
        case .codex: line.containsTypeValue(in: Self.codexMarkers)
        case .claude: line.containsClaudeMarkers()
        }
        guard containsMarker, let baseAddress = line.baseAddress else {
            return nil
        }
        let data = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: baseAddress),
            count: line.count,
            deallocator: .none
        )
        switch self {
        case .codex(var parser):
            let event = parser.parse(data, source: source, decoder: decoder)
            self = .codex(parser)
            return event
        case .claude:
            return parseClaudeLog(data, decoder: decoder)
        }
    }

    fileprivate static let typeKey = Data("\"type\"".utf8)
    fileprivate static let codexMarkers = [
        CodexRecordKind.sessionMeta.jsonStringMarker,
        CodexRecordKind.turnContext.jsonStringMarker,
        CodexPayloadKind.tokenCount.jsonStringMarker,
    ]
    fileprivate static let claudeAssistantMarker = ClaudeRecordKind.assistant.jsonStringMarker
}

private extension UnsafeRawBufferPointer {
    func containsClaudeMarkers() -> Bool {
        guard
            containsTypeValue(in: [UsageFileParserState.claudeAssistantMarker]),
            let baseAddress
        else {
            return false
        }
        return ClaudeMessage.usageMarker.withUnsafeBytes { marker in
            memmem(baseAddress, count, marker.baseAddress, marker.count) != nil
        }
    }

    func containsTypeValue(in values: [Data]) -> Bool {
        guard let baseAddress else {
            return false
        }
        let bytes = bindMemory(to: UInt8.self)
        var searchStart = 0

        while searchStart < count {
            let match = UsageFileParserState.typeKey.withUnsafeBytes { key in
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

            var valueStart = baseAddress.distance(to: UnsafeRawPointer(match))
                + UsageFileParserState.typeKey.count
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

    func matches(_ data: Data, at index: Int) -> Bool {
        guard
            let baseAddress,
            index <= count,
            count - index >= data.count
        else {
            return false
        }
        return data.withUnsafeBytes { candidate in
            guard let candidateAddress = candidate.baseAddress else {
                return false
            }
            return memcmp(
                baseAddress.advanced(by: index),
                candidateAddress,
                candidate.count
            ) == 0
        }
    }
}

private extension UInt8 {
    var isJSONWhitespace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}

struct CodexLogParser: Sendable {
    private var threadID: String?
    private var turn: CodexTurn?
    private var previousTotalUsage: CodexTokenUsage?

    mutating func parse(
        _ line: Data,
        source: String,
        decoder: JSONDecoder
    ) -> UsageEvent? {
        guard let record = try? decoder.decode(CodexLogRecord.self, from: line) else {
            return nil
        }

        switch record {
        case .sessionMeta(let threadID):
            self.threadID = threadID
        case .turnContext(let turn):
            self.turn = turn
        case .clearTurn:
            turn = nil
        case .tokenCount(let tokenCount):
            return parseTokenCount(tokenCount, source: source)
        case .other:
            break
        }

        return nil
    }

    private mutating func parseTokenCount(
        _ record: CodexTokenCount,
        source: String
    ) -> UsageEvent? {
        let lastUsage = record.info.lastTokenUsage
        let totalUsage = record.info.totalTokenUsage

        if record.info.isSyntheticContextFill(previous: previousTotalUsage) {
            previousTotalUsage = totalUsage
            return nil
        }
        defer { previousTotalUsage = totalUsage }

        guard !lastUsage.componentsAreZero, previousTotalUsage != totalUsage else {
            return nil
        }
        guard
            let timestampValue = record.timestamp,
            let timestamp = parseUsageTimestamp(timestampValue),
            let turn
        else {
            return nil
        }

        return .codex(UsageEvent.Codex(
            threadID: threadID ?? source,
            turnID: turn.id,
            ordinal: record.ordinal,
            details: UsageEvent.Details(
                timestamp: timestamp,
                model: turn.model,
                reasoningEffort: turn.reasoningEffort,
                tokens: lastUsage.tokens
            ),
            reasoningOutput: lastUsage.reasoningOutput,
            cumulativeTotal: totalUsage.total
        ))
    }
}

private func parseClaudeLog(_ line: Data, decoder: JSONDecoder) -> UsageEvent? {
    guard
        let record = try? decoder.decode(ClaudeLogRecord.self, from: line),
        record.type == .assistant,
        let timestampValue = record.timestamp,
        let timestamp = parseUsageTimestamp(timestampValue),
        let message = record.message,
        let messageID = nonempty(message.id),
        let requestID = nonempty(record.requestID),
        let model = nonempty(message.model),
        let usage = message.usage
    else {
        return nil
    }

    return .claude(UsageEvent.Claude(
        messageID: messageID,
        requestID: requestID,
        details: UsageEvent.Details(
            timestamp: timestamp,
            model: model,
            reasoningEffort: nonempty(record.effort),
            tokens: usage.tokens
        ),
        speed: usage.speed,
        inferenceGeo: nonempty(usage.inferenceGeo),
        webSearchRequests: usage.webSearchRequests
    ))
}

private func nonempty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}

private enum CodexLogRecord: Decodable {
    case sessionMeta(threadID: String?)
    case turnContext(CodexTurn)
    case clearTurn
    case tokenCount(CodexTokenCount)
    case other

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case ordinal
        case type
        case payload
    }

    private enum SessionMetaKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
    }

    private enum TurnContextKeys: String, CodingKey {
        case turnID = "turn_id"
        case model
        case effort
    }

    private enum EventMessageKeys: String, CodingKey {
        case type
        case info
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CodexRecordKind.self, forKey: .type) {
        case .sessionMeta:
            let payload = try container.nestedContainer(
                keyedBy: SessionMetaKeys.self,
                forKey: .payload
            )
            let id = try payload.decodeIfPresent(String.self, forKey: .id)
            let sessionID = try payload.decodeIfPresent(String.self, forKey: .sessionID)
            self = .sessionMeta(
                threadID: nonempty(id) ?? nonempty(sessionID)
            )
        case .turnContext:
            let payload = try container.nestedContainer(
                keyedBy: TurnContextKeys.self,
                forKey: .payload
            )
            guard let model = nonempty(
                try payload.decodeIfPresent(String.self, forKey: .model)
            ) else {
                self = .clearTurn
                return
            }
            self = .turnContext(CodexTurn(
                id: nonempty(try payload.decodeIfPresent(String.self, forKey: .turnID)),
                model: model,
                reasoningEffort: nonempty(
                    try payload.decodeIfPresent(String.self, forKey: .effort)
                )
            ))
        case .eventMessage:
            let payload = try container.nestedContainer(
                keyedBy: EventMessageKeys.self,
                forKey: .payload
            )
            guard
                try payload.decodeIfPresent(CodexPayloadKind.self, forKey: .type) == .tokenCount,
                let info = try payload.decodeIfPresent(CodexTokenInfo.self, forKey: .info)
            else {
                self = .other
                return
            }
            self = .tokenCount(CodexTokenCount(
                timestamp: try container.decodeIfPresent(String.self, forKey: .timestamp),
                ordinal: try container.decodeIfPresent(UInt64.self, forKey: .ordinal),
                info: info
            ))
        case .other:
            self = .other
        }
    }
}

private struct CodexTurn: Sendable {
    let id: String?
    let model: String
    let reasoningEffort: String?
}

private struct CodexTokenCount {
    let timestamp: String?
    let ordinal: UInt64?
    let info: CodexTokenInfo
}

private struct CodexTokenInfo: Decodable {
    let lastTokenUsage: CodexTokenUsage
    let totalTokenUsage: CodexTokenUsage
    let modelContextWindow: Int64?

    private enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case modelContextWindow = "model_context_window"
    }

    func isSyntheticContextFill(previous: CodexTokenUsage?) -> Bool {
        guard
            let modelContextWindow,
            modelContextWindow >= 0,
            lastTokenUsage.componentsAreZero,
            totalTokenUsage.componentsAreZero,
            totalTokenUsage.total == modelContextWindow
        else {
            return false
        }

        let previousTotal = previous?.total ?? 0
        let expectedLastTotal: Int64
        if modelContextWindow > previousTotal {
            let (difference, overflow) = modelContextWindow
                .subtractingReportingOverflow(previousTotal)
            guard !overflow else {
                return false
            }
            expectedLastTotal = difference
        } else {
            expectedLastTotal = 0
        }
        return lastTokenUsage.total == expectedLastTotal
    }
}

private struct CodexTokenUsage: Decodable, Equatable, Sendable {
    let input: Int64
    let cachedInput: Int64
    let cacheWriteInput: Int64
    let output: Int64
    let reasoningOutput: Int64
    let total: Int64

    var componentsAreZero: Bool {
        input == 0
            && cachedInput == 0
            && cacheWriteInput == 0
            && output == 0
            && reasoningOutput == 0
    }

    var tokens: UsageTokens {
        UsageTokens(
            uncachedInput: input - cachedInput - cacheWriteInput,
            cachedInput: cachedInput,
            cacheWrite: .fiveMinute(cacheWriteInput),
            output: output,
            processed: total
        )
    }

    private enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cachedInput = "cached_input_tokens"
        case cacheWriteInput = "cache_write_input_tokens"
        case output = "output_tokens"
        case reasoningOutput = "reasoning_output_tokens"
        case total = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decode(Int64.self, forKey: .input)
        cachedInput = try container.decodeIfPresent(Int64.self, forKey: .cachedInput) ?? 0
        cacheWriteInput = try container.decodeIfPresent(Int64.self, forKey: .cacheWriteInput) ?? 0
        output = try container.decode(Int64.self, forKey: .output)
        reasoningOutput = try container.decodeIfPresent(Int64.self, forKey: .reasoningOutput) ?? 0
        total = try container.decode(Int64.self, forKey: .total)

        let (cachedAndWritten, overflow) = cachedInput.addingReportingOverflow(cacheWriteInput)
        guard
            input >= 0,
            cachedInput >= 0,
            cacheWriteInput >= 0,
            output >= 0,
            reasoningOutput >= 0,
            reasoningOutput <= output,
            total >= 0,
            !overflow,
            cachedAndWritten <= input
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .total,
                in: container,
                debugDescription: "invalid token usage"
            )
        }
    }
}

private struct ClaudeLogRecord: Decodable {
    let type: ClaudeRecordKind
    let timestamp: String?
    let requestID: String?
    let effort: String?
    let message: ClaudeMessage?

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case requestID = "requestId"
        case effort
        case message
    }
}

private struct ClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeUsage?

    fileprivate static let usageMarker = Data(("\"" + CodingKeys.usage.rawValue + "\"").utf8)

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case usage
    }
}

private struct ClaudeUsage: Decodable {
    let tokens: UsageTokens
    let speed: UsageEvent.Claude.Speed
    let inferenceGeo: String?
    let webSearchRequests: Int64

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreation = "cache_creation"
        case speed
        case inferenceGeo = "inference_geo"
        case serverToolUse = "server_tool_use"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let input = try container.decode(Int64.self, forKey: .inputTokens)
        let cacheRead = try container.decodeIfPresent(Int64.self, forKey: .cacheReadInputTokens) ?? 0
        let cacheWrite = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationInputTokens) ?? 0
        let output = try container.decode(Int64.self, forKey: .outputTokens)
        let cacheCreation = try container.decodeIfPresent(
            ClaudeCacheCreation.self,
            forKey: .cacheCreation
        )
        let cacheWrite5Minute: Int64
        let cacheWrite1Hour: Int64
        if let cacheCreation {
            cacheWrite5Minute = cacheCreation.ephemeral5MinuteInputTokens ?? 0
            cacheWrite1Hour = cacheCreation.ephemeral1HourInputTokens ?? 0
        } else {
            cacheWrite5Minute = cacheWrite
            cacheWrite1Hour = 0
        }
        let (splitCacheWrite, cacheOverflow) = cacheWrite5Minute
            .addingReportingOverflow(cacheWrite1Hour)

        switch try container.decodeIfPresent(String.self, forKey: .speed) {
        case nil:
            speed = .implicitStandard
        case "standard":
            speed = .standard
        case "fast":
            speed = .fast
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .speed,
                in: container,
                debugDescription: "unknown speed"
            )
        }

        inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo)
        webSearchRequests = try container.decodeIfPresent(
            ClaudeServerToolUse.self,
            forKey: .serverToolUse
        )?.webSearchRequests ?? 0

        let values = [input, cacheRead, cacheWrite5Minute, cacheWrite1Hour, output]
        var processed: Int64 = 0
        for value in values {
            let (sum, overflow) = processed.addingReportingOverflow(value)
            guard value >= 0, !overflow else {
                throw DecodingError.dataCorruptedError(
                    forKey: .inputTokens,
                    in: container,
                    debugDescription: "invalid token usage"
                )
            }
            processed = sum
        }
        guard
            !cacheOverflow,
            splitCacheWrite == cacheWrite,
            webSearchRequests >= 0
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .cacheCreationInputTokens,
                in: container,
                debugDescription: "invalid usage metadata"
            )
        }

        tokens = UsageTokens(
            uncachedInput: input,
            cachedInput: cacheRead,
            cacheWrite: cacheCreation == nil
                ? .fiveMinute(cacheWrite5Minute)
                : .byDuration(
                    fiveMinute: cacheWrite5Minute,
                    oneHour: cacheWrite1Hour
                ),
            output: output,
            processed: processed
        )
    }
}

private struct ClaudeCacheCreation: Decodable {
    let ephemeral5MinuteInputTokens: Int64?
    let ephemeral1HourInputTokens: Int64?

    private enum CodingKeys: String, CodingKey {
        case ephemeral5MinuteInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1HourInputTokens = "ephemeral_1h_input_tokens"
    }
}

private struct ClaudeServerToolUse: Decodable {
    let webSearchRequests: Int64?

    private enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
    }
}
