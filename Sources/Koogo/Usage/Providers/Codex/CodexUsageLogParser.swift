import Foundation

private enum CodexRecordKind: String, LogRecordKind {
    case turnContext = "turn_context"
    case eventMessage = "event_msg"
    case other
}

private enum CodexPayloadKind: String, LogRecordKind {
    case tokenCount = "token_count"
    case other
}

struct CodexLogParser: UsageLogParser {
    private static let eventMarkers = [
        CodexRecordKind.turnContext.jsonStringMarker,
        CodexPayloadKind.tokenCount.jsonStringMarker,
    ]

    private var turn: CodexTurn?
    private var previousTotalUsage: CodexTokenUsage?

    func mayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool {
        Self.eventMarkers.contains { line.contains($0) }
    }

    mutating func parse(
        _ line: Data,
        decoder: JSONDecoder
    ) throws -> UsageLineOutcome? {
        switch try decoder.decode(CodexLogRecord.self, from: line) {
        case .turnContext(let turn):
            self.turn = turn
        case .tokenCount(let tokenCount):
            return try parseTokenCount(tokenCount)
        case .other:
            break
        }
        return nil
    }

    private mutating func parseTokenCount(_ record: CodexTokenCount) throws -> UsageLineOutcome? {
        let lastUsage = record.info.lastTokenUsage
        let totalUsage = record.info.totalTokenUsage

        defer { previousTotalUsage = totalUsage }

        // `CodexTokenUsage.init` bounds cached + cache-write tokens by input and reasoning tokens by output,
        // so a request without input or output bills nothing.
        guard lastUsage.input > 0 || lastUsage.output > 0, previousTotalUsage != totalUsage else {
            return nil
        }
        guard let turn else {
            return nil
        }
        guard let timestamp = parseUsageTimestamp(record.timestamp) else {
            throw MalformedUsageRecord()
        }
        guard let quote = CodexUsagePricing.quote(model: turn.model, tokens: lastUsage) else {
            return .unpricedModel(id: turn.model, timestamp: timestamp)
        }

        return .event(
            UsageEvent(
                key: .codex(turnID: turn.id, cumulativeTotal: totalUsage.processed),
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: lastUsage.processed,
                    costUSD: quote.costUSD,
                    modelTurn: UsageRecord.ModelTurn(
                        model: quote.model,
                        reasoningEffort: turn.reasoningEffort
                    )
                )
            )
        )
    }
}

private enum CodexLogRecord: Decodable {
    case turnContext(CodexTurn)
    case tokenCount(CodexTokenCount)
    case other

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CodexRecordKind.self, forKey: .type) {
        case .turnContext:
            self = .turnContext(try container.decode(CodexTurn.self, forKey: .payload))
        case .eventMessage:
            let payload = try container.decode(CodexEventMessage.self, forKey: .payload)
            guard payload.type == .tokenCount, let info = payload.info else {
                self = .other
                return
            }
            self = .tokenCount(
                CodexTokenCount(
                    timestamp: try container.decode(String.self, forKey: .timestamp),
                    info: info
                )
            )
        case .other:
            self = .other
        }
    }
}

private struct CodexEventMessage: Decodable {
    let type: CodexPayloadKind
    let info: CodexTokenInfo?
}

private struct CodexTurn: Decodable, Sendable {
    let id: String
    let model: String
    let reasoningEffort: String?

    private enum CodingKeys: String, CodingKey {
        case id = "turn_id"
        case model
        case reasoningEffort = "effort"
    }
}

private struct CodexTokenCount {
    let timestamp: String
    let info: CodexTokenInfo
}

private struct CodexTokenInfo: Decodable {
    let lastTokenUsage: CodexTokenUsage
    let totalTokenUsage: CodexTokenUsage
    // decoding this field still rejects malformed context-window values.
    let modelContextWindow: Int64?

    private enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
        case totalTokenUsage = "total_token_usage"
        case modelContextWindow = "model_context_window"
    }
}

extension CodexTokenUsage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cachedInput = "cached_input_tokens"
        case cacheWrite = "cache_write_input_tokens"
        case output = "output_tokens"
        case reasoningOutput = "reasoning_output_tokens"
        case processed = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let usage = CodexTokenUsage(
                input: try container.decode(UInt64.self, forKey: .input),
                cachedInput: try container.decode(UInt64.self, forKey: .cachedInput),
                cacheWrite: try container.decodeIfPresent(UInt64.self, forKey: .cacheWrite) ?? 0,
                output: try container.decode(UInt64.self, forKey: .output),
                reasoningOutput: try container.decode(UInt64.self, forKey: .reasoningOutput),
                processed: try container.decode(UInt64.self, forKey: .processed)
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .processed,
                in: container,
                debugDescription: "invalid token usage"
            )
        }
        self = usage
    }
}
