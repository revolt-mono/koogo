import Foundation

private enum ClaudeRecordKind: String, LogRecordKind {
    case assistant
    case other
}

struct ClaudeLogParser: UsageLogParser {
    private static let eventMarkers = [
        ClaudeRecordKind.assistant.jsonStringMarker,
        ClaudeMessage.usageMarker,
    ]

    func mayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool {
        Self.eventMarkers.allSatisfy { line.contains($0) }
    }

    func parse(_ line: Data, decoder: JSONDecoder) -> UsageLineOutcome? {
        guard
            let record = try? decoder.decode(ClaudeLogRecord.self, from: line),
            record.type == .assistant,
            let timestampValue = record.timestamp,
            let timestamp = parseUsageTimestamp(timestampValue),
            let message = record.message,
            let messageID = nonEmpty(message.id),
            let requestID = nonEmpty(record.requestID),
            let model = nonEmpty(message.model),
            let usage = message.usage
        else {
            return nil
        }
        guard let quote = ClaudeUsagePricing.quote(model: model, usage: usage) else {
            return .unpricedModel(id: model, timestamp: timestamp)
        }

        let reasoningEffort = nonEmpty(record.effort)
        return .event(
            .claude(
                id: UsageEvent.ClaudeID(
                    messageID: messageID,
                    requestID: requestID
                ),
                revision: UsageEvent.ClaudeRevision(
                    usage: UsageRecord(
                        timestamp: timestamp,
                        processedTokens: usage.tokens.processed,
                        costUSD: quote.costUSD,
                        modelTurn: UsageRecord.ModelTurn(
                            model: quote.model,
                            reasoningEffort: reasoningEffort
                        )
                    ),
                    outputTokens: usage.tokens.output,
                    metadataCompleteness: usage.metadataCompleteness(
                        reasoningEffort: reasoningEffort
                    )
                )
            )
        )
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
    let usage: ClaudeBillableUsage?

    static let usageMarker = Data("\"\(CodingKeys.usage.rawValue)\"".utf8)

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case usage
    }
}

extension ClaudeBillableUsage: Decodable {
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
        speed =
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
        inferenceGeo = try container.decodeIfPresent(String.self, forKey: .inferenceGeo)
        webSearchRequests =
            try container.decodeIfPresent(
                ClaudeServerToolUse.self,
                forKey: .serverToolUse
            )?.webSearchRequests ?? 0

        guard
            let tokens = ClaudeTokenUsage(
                input: try container.decode(UInt64.self, forKey: .inputTokens),
                cacheRead: try container.decodeIfPresent(
                    UInt64.self,
                    forKey: .cacheReadInputTokens
                ) ?? 0,
                cacheCreation: try Self.cacheCreation(
                    aggregate: container.decodeIfPresent(
                        UInt64.self,
                        forKey: .cacheCreationInputTokens
                    ) ?? 0,
                    breakdown: container.decodeIfPresent(
                        ClaudeCacheCreationBreakdown.self,
                        forKey: .cacheCreation
                    ),
                    in: container
                ),
                output: try container.decode(UInt64.self, forKey: .outputTokens)
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .inputTokens,
                in: container,
                debugDescription: "invalid token usage"
            )
        }
        self.tokens = tokens
    }

    private static func cacheCreation(
        aggregate: UInt64,
        breakdown: ClaudeCacheCreationBreakdown?,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ClaudeTokenUsage.CacheCreation {
        guard let breakdown else {
            return .aggregate(aggregate)
        }
        let fiveMinute = breakdown.ephemeral5MinuteInputTokens ?? 0
        let oneHour = breakdown.ephemeral1HourInputTokens ?? 0
        let (total, overflow) = fiveMinute.addingReportingOverflow(oneHour)
        guard !overflow, total == aggregate else {
            throw DecodingError.dataCorruptedError(
                forKey: .cacheCreationInputTokens,
                in: container,
                debugDescription: "invalid usage metadata"
            )
        }
        return .byDuration(fiveMinute: fiveMinute, oneHour: oneHour)
    }
}

private struct ClaudeCacheCreationBreakdown: Decodable {
    let ephemeral5MinuteInputTokens: UInt64?
    let ephemeral1HourInputTokens: UInt64?

    private enum CodingKeys: String, CodingKey {
        case ephemeral5MinuteInputTokens = "ephemeral_5m_input_tokens"
        case ephemeral1HourInputTokens = "ephemeral_1h_input_tokens"
    }
}

private struct ClaudeServerToolUse: Decodable {
    let webSearchRequests: UInt64?

    private enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}
