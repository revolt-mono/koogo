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
            let turn,
            let quote = CodexUsagePricing.quote(model: turn.model, tokens: lastUsage)
        else {
            return nil
        }

        return .codex(
            id: UsageEvent.CodexID(
                threadID: threadID ?? source,
                turnID: turn.id,
                ordinal: record.ordinal,
                timestamp: timestamp,
                model: turn.model,
                tokens: lastUsage,
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
    }

    private static let eventMarkers = [
        CodexRecordKind.sessionMeta.jsonStringMarker,
        CodexRecordKind.turnContext.jsonStringMarker,
        CodexPayloadKind.tokenCount.jsonStringMarker,
    ]
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(CodexRecordKind.self, forKey: .type) {
        case .sessionMeta:
            let payload = try container.decode(CodexSessionMetadata.self, forKey: .payload)
            self = .sessionMeta(threadID: nonempty(payload.id) ?? nonempty(payload.sessionID))
        case .turnContext:
            let payload = try container.decode(CodexTurnContext.self, forKey: .payload)
            guard let model = nonempty(payload.model) else {
                self = .clearTurn
                return
            }
            self = .turnContext(
                CodexTurn(
                    id: nonempty(payload.turnID),
                    model: model,
                    reasoningEffort: nonempty(payload.effort)
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
                    timestamp: try container.decodeIfPresent(String.self, forKey: .timestamp),
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
    let id: String?
    let sessionID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
    }
}

private struct CodexTurnContext: Decodable {
    let turnID: String?
    let model: String?
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
            totalTokenUsage.processed == modelContextWindow
        else {
            return false
        }

        let previousTotal = previous?.processed ?? 0
        let expectedLastTotal: Int64
        if modelContextWindow > previousTotal {
            let (difference, overflow) =
                modelContextWindow
                .subtractingReportingOverflow(previousTotal)
            guard !overflow else {
                return false
            }
            expectedLastTotal = difference
        } else {
            expectedLastTotal = 0
        }
        return lastTokenUsage.processed == expectedLastTotal
    }
}

extension CodexTokenUsage {
    fileprivate var componentsAreZero: Bool {
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
        input = try container.decode(Int64.self, forKey: .input)
        cachedInput = try container.decodeIfPresent(Int64.self, forKey: .cachedInput) ?? 0
        cacheWrite = try container.decodeIfPresent(Int64.self, forKey: .cacheWrite) ?? 0
        output = try container.decode(Int64.self, forKey: .output)
        reasoningOutput = try container.decodeIfPresent(Int64.self, forKey: .reasoningOutput) ?? 0
        processed = try container.decode(Int64.self, forKey: .processed)

        let (cachedAndWritten, overflow) = cachedInput.addingReportingOverflow(cacheWrite)
        guard
            input >= 0,
            cachedInput >= 0,
            cacheWrite >= 0,
            output >= 0,
            reasoningOutput >= 0,
            reasoningOutput <= output,
            processed >= 0,
            !overflow,
            cachedAndWritten <= input
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .processed,
                in: container,
                debugDescription: "invalid token usage"
            )
        }
    }
}
