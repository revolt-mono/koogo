import Foundation

private enum ClaudeRecordKind: String, LogRecordKind {
    case assistant
    case other
}

func claudeLogMayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool {
    guard line.containsTypeValue(in: [ClaudeRecordKind.assistant.jsonStringMarker]),
        let baseAddress = line.baseAddress
    else {
        return false
    }
    return ClaudeMessage.usageMarker.withUnsafeBytes { marker in
        memmem(baseAddress, line.count, marker.baseAddress, marker.count) != nil
    }
}

func parseClaudeLog(_ line: Data, decoder: JSONDecoder) -> UsageEvent? {
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

    return .claude(
        UsageEvent.Claude(
            messageID: messageID,
            requestID: requestID,
            details: UsageEvent.Details(
                timestamp: timestamp,
                model: model,
                reasoningEffort: nonempty(record.effort)
            ),
            tokens: usage.tokens,
            speed: usage.speed,
            inferenceGeo: nonempty(usage.inferenceGeo),
            webSearchRequests: usage.webSearchRequests
        )
    )
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

    static let usageMarker = Data(("\"" + CodingKeys.usage.rawValue + "\"").utf8)

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case usage
    }
}

private struct ClaudeUsage: Decodable {
    let tokens: UsageEvent.Claude.Tokens
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
        let cacheCreation = try Self.cacheCreation(
            aggregate: cacheWrite,
            breakdown: container.decodeIfPresent(
                ClaudeCacheCreationBreakdown.self,
                forKey: .cacheCreation
            ),
            in: container
        )

        speed = try Self.speed(in: container)
        inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo)
        webSearchRequests =
            try container.decodeIfPresent(
                ClaudeServerToolUse.self,
                forKey: .serverToolUse
            )?.webSearchRequests ?? 0

        _ = try [input, cacheRead, cacheWrite, output]
            .reduce(into: Int64.zero) { processed, value in
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
        guard webSearchRequests >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .serverToolUse,
                in: container,
                debugDescription: "invalid usage metadata"
            )
        }
        tokens = UsageEvent.Claude.Tokens(
            input: input,
            cacheRead: cacheRead,
            cacheCreation: cacheCreation,
            output: output
        )
    }

    private static func cacheCreation(
        aggregate: Int64,
        breakdown: ClaudeCacheCreationBreakdown?,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UsageEvent.Claude.Tokens.CacheCreation {
        guard let breakdown else {
            return .aggregate(aggregate)
        }
        let fiveMinute = breakdown.ephemeral5MinuteInputTokens ?? 0
        let oneHour = breakdown.ephemeral1HourInputTokens ?? 0
        let (total, overflow) = fiveMinute.addingReportingOverflow(oneHour)
        guard fiveMinute >= 0, oneHour >= 0, !overflow, total == aggregate else {
            throw DecodingError.dataCorruptedError(
                forKey: .cacheCreationInputTokens,
                in: container,
                debugDescription: "invalid usage metadata"
            )
        }
        return .byDuration(fiveMinute: fiveMinute, oneHour: oneHour)
    }

    private static func speed(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UsageEvent.Claude.Speed {
        switch try container.decodeIfPresent(String.self, forKey: .speed) {
        case nil: .implicitStandard
        case "standard": .standard
        case "fast": .fast
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .speed,
                in: container,
                debugDescription: "unknown speed"
            )
        }
    }
}

private struct ClaudeCacheCreationBreakdown: Decodable {
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
