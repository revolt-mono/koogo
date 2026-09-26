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
            let timestamp = parseUsageTimestamp(record.timestamp),
            let messageID = nonEmpty(record.message.id),
            let requestID = nonEmpty(record.requestID),
            let model = nonEmpty(record.message.model)
        else {
            return nil
        }
        let usage = record.message.usage
        let isFast: Bool
        switch usage.speed {
        case nil, "standard": isFast = false
        case "fast": isFast = true
        default: return .unpricedModel(id: model, timestamp: timestamp)
        }
        let billable = ClaudeBillableUsage(
            tokens: usage.tokens,
            isFast: isFast,
            isUSInference: usage.geo == "us",
            webSearchRequests: usage.webSearchRequests
        )
        guard let quote = ClaudeUsagePricing.quote(model: model, usage: billable) else {
            return .unpricedModel(id: model, timestamp: timestamp)
        }

        let reasoningEffort = nonEmpty(record.effort)
        return .event(
            UsageEvent(
                key: .claude(messageID: messageID, requestID: requestID),
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.tokens.processed,
                    costUSD: quote.costUSD,
                    modelTurn: UsageRecord.ModelTurn(
                        model: quote.model,
                        reasoningEffort: reasoningEffort
                    )
                ),
                revision: Self.revision(of: usage, reasoningEffort: reasoningEffort)
            )
        )
    }

    /// Claude logs partial copies of one request; the copy with more output wins, then the one
    /// with more explicit metadata: a logged speed, a cache split by duration, a logged effort.
    private static func revision(of usage: ClaudeLoggedUsage, reasoningEffort: String?) -> UsageEvent.Revision {
        let explicitCacheDuration =
            switch usage.tokens.cacheCreation {
            case .aggregate: 0
            case .byDuration: 1
            }
        return UsageEvent.Revision(
            outputTokens: usage.tokens.output,
            metadataCompleteness: (usage.speed == nil ? 0 : 1)
                + explicitCacheDuration
                + (reasoningEffort == nil ? 0 : 1)
        )
    }
}

private struct ClaudeLogRecord: Decodable {
    let type: ClaudeRecordKind
    let timestamp: String
    let requestID: String
    let effort: String?
    let message: ClaudeMessage

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case requestID = "requestId"
        case effort
        case message
    }
}

private struct ClaudeMessage: Decodable {
    let id: String
    let model: String
    let usage: ClaudeLoggedUsage

    static let usageMarker = Data("\"\(CodingKeys.usage.rawValue)\"".utf8)

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case usage
    }
}

/// The usage object as logged, with token amounts validated; speed and geo stay raw until the parser reads them.
private struct ClaudeLoggedUsage: Decodable {
    let tokens: ClaudeTokenUsage
    let speed: String?
    let geo: String?
    let webSearchRequests: UInt64

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreation = "cache_creation"
        case speed
        case geo = "inference_geo"
        case serverToolUse = "server_tool_use"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speed = try container.decodeIfPresent(String.self, forKey: .speed)
        geo = try container.decodeIfPresent(String.self, forKey: .geo)
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
