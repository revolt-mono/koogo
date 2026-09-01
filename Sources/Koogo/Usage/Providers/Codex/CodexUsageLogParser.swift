import Foundation

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

struct CodexLogParser: Sendable {
    private var threadID: String?
    private var turn: CodexTurn?
    private var previousTotalUsage: CodexTokenUsage?

    static func mayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool {
        line.containsTypeValue(in: eventMarkers)
    }

    mutating func parse(
        _ line: Data,
        decoder: JSONDecoder
    ) -> UsageLineOutcome? {
        guard let record = try? decoder.decode(CodexLogRecord.self, from: line) else {
            return nil
        }

        switch record {
        case .sessionMeta(let threadID):
            self.threadID = threadID
        case .turnContext(let turn):
            self.turn = turn
        case .tokenCount(let tokenCount):
            return parseTokenCount(tokenCount)
        case .other:
            break
        }
        return nil
    }

    private mutating func parseTokenCount(_ record: CodexTokenCount) -> UsageLineOutcome? {
        let lastUsage = record.info.lastTokenUsage
        let totalUsage = record.info.totalTokenUsage

        if record.info.isSyntheticContextFill(previous: previousTotalUsage) {
            previousTotalUsage = totalUsage
            return nil
        }
        defer { previousTotalUsage = totalUsage }

        guard !lastUsage.billableTokensAreZero, previousTotalUsage != totalUsage else {
            return nil
        }
        guard
            let timestamp = parseUsageTimestamp(record.timestamp),
            let threadID,
            let turn
        else {
            return nil
        }
        guard let quote = CodexUsagePricing.quote(model: turn.model, tokens: lastUsage) else {
            return .unpricedModel(id: turn.model, timestamp: timestamp)
        }

        return .event(
            .codex(
                id: UsageEvent.CodexID(
                    threadID: threadID,
                    turnID: turn.id,
                    ordinal: record.ordinal,
                    timestamp: timestamp,
                    cumulativeTotal: totalUsage.processed
                ),
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

    private static let eventMarkers = [
        CodexRecordKind.sessionMeta.jsonStringMarker,
        CodexRecordKind.turnContext.jsonStringMarker,
        CodexPayloadKind.tokenCount.jsonStringMarker,
    ]
}

private enum CodexLogRecord: Decodable {
    case sessionMeta(threadID: String)
    case turnContext(CodexTurn)
    case tokenCount(CodexTokenCount)
    case other

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case ordinal
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CodexRecordKind.self, forKey: .type) {
        case .sessionMeta:
            self = .sessionMeta(
                threadID: try container.decode(CodexSessionMetadata.self, forKey: .payload).id
            )
        case .turnContext:
            let payload = try container.decode(CodexTurnContext.self, forKey: .payload)
            self = .turnContext(
                CodexTurn(
                    id: payload.turnID,
                    model: payload.model,
                    reasoningEffort: payload.effort
                )
            )
        case .eventMessage:
            let payload = try container.decode(CodexEventMessage.self, forKey: .payload)
            guard payload.type == .tokenCount, let info = payload.info else {
                self = .other
                return
            }
            self = .tokenCount(
                CodexTokenCount(
                    timestamp: try container.decode(String.self, forKey: .timestamp),
                    ordinal: try container.decodeIfPresent(UInt64.self, forKey: .ordinal),
                    info: info
                )
            )
        case .other:
            self = .other
        }
    }
}

private struct CodexSessionMetadata: Decodable {
    let id: String
}

private struct CodexTurnContext: Decodable {
    let turnID: String?
    let model: String
    let effort: String?

    private enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case model
        case effort
    }
}

private struct CodexEventMessage: Decodable {
    let type: CodexPayloadKind
    let info: CodexTokenInfo?
}

private struct CodexTurn: Sendable {
    let id: String?
    let model: String
    let reasoningEffort: String?
}

private struct CodexTokenCount {
    let timestamp: String
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
            let contextWindow = UInt64(exactly: modelContextWindow),
            lastTokenUsage.billableTokensAreZero,
            totalTokenUsage.billableTokensAreZero,
            totalTokenUsage.processed == contextWindow
        else {
            return false
        }

        let previousTotal = previous?.processed ?? 0
        return lastTokenUsage.processed
            == (contextWindow > previousTotal ? contextWindow - previousTotal : 0)
    }
}

extension CodexTokenUsage {
    fileprivate var billableTokensAreZero: Bool {
        input == 0
            && cachedInput == 0
            && cacheWrite == 0
            && output == 0
            && reasoningOutput == 0
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
