import Foundation

struct CodexUsageLogParser: UsageLogParser {
    private var turn: CodexTurn?
    private var previousTotalUsage: CodexTokenUsage?

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        switch try CodexRecord(line) {
        case .turnContext(let payload):
            turn = try CodexTurn(payload)
            return nil
        case .eventMessage(let payload, let timestamp):
            guard let tokenCount = try CodexTokenCount(payload) else {
                return nil
            }
            guard let timestamp = try timestamp?.string() else {
                throw MalformedUsageRecord()
            }
            return try bill(tokenCount, at: timestamp)
        case nil:
            return nil
        }
    }

    private mutating func bill(
        _ tokenCount: CodexTokenCount,
        at loggedTimestamp: String
    ) throws
        -> UsageLineOutcome?
    {
        let lastUsage = tokenCount.last
        let totalUsage = tokenCount.total

        defer { previousTotalUsage = totalUsage }

        guard lastUsage.input > 0 || lastUsage.output > 0, previousTotalUsage != totalUsage else {
            return nil
        }
        guard let turn else {
            return nil
        }
        guard let timestamp = Date(iso8601: loggedTimestamp) else {
            throw MalformedUsageRecord()
        }
        guard let quote = CodexUsagePricing.quote(model: turn.model, tokens: lastUsage) else {
            return .unpricedModel(id: turn.model, timestamp: timestamp)
        }

        return .event(
            UsageEvent(
                id: .codex(turnID: turn.id, cumulativeTotal: totalUsage.processed),
                record: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: lastUsage.processed,
                    quote: quote,
                    reasoningEffort: turn.reasoningEffort
                )
            )
        )
    }
}

private enum CodexRecord {
    case turnContext(payload: JSONValue)
    case eventMessage(payload: JSONValue, timestamp: JSONValue?)

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard let record = JSONValue(object: line) else {
            return nil
        }
        let (kind, timestamp, payload) = try record.fields(
            .kind("type") { $0.isString("turn_context") || $0.isString("event_msg") },
            .value("timestamp"),
            .value("payload")
        )
        guard let kind else {
            return nil
        }
        let isTurnContext = kind.isString("turn_context")
        guard let payload else {
            throw MalformedUsageRecord()
        }
        self = isTurnContext ? .turnContext(payload: payload) : .eventMessage(payload: payload, timestamp: timestamp)
    }
}

private struct CodexTurn {
    let id: String
    let model: String
    let reasoningEffort: String?

    init(_ payload: JSONValue) throws {
        let (id, model, reasoningEffort) = try payload.fields(.string("turn_id"), .string("model"), .string("effort"))
        guard let id, let model else {
            throw MalformedUsageRecord()
        }
        self.id = id
        self.model = model
        self.reasoningEffort = reasoningEffort
    }
}

private struct CodexTokenCount {
    let last: CodexTokenUsage
    let total: CodexTokenUsage

    init?(_ payload: JSONValue) throws {
        let (kind, info) = try payload.fields(.kind("type") { $0.isString("token_count") }, .value("info"))
        guard kind != nil, let info = info?.nonNull else {
            return nil
        }
        let (last, total, _) = try info.fields(
            JSONField("last_token_usage", CodexTokenUsage.init(_:)),
            JSONField("total_token_usage", CodexTokenUsage.init(_:)),
            .int64("model_context_window")
        )
        guard let last, let total else {
            throw MalformedUsageRecord()
        }
        self.last = last
        self.total = total
    }
}

struct CodexTokenUsage: Equatable, Sendable {
    let input: UInt64
    let cachedInput: UInt64
    let cacheWrite: UInt64
    let output: UInt64
    let processed: UInt64

    init?(
        input: UInt64,
        cachedInput: UInt64,
        cacheWrite: UInt64,
        output: UInt64,
        reasoningOutput: UInt64,
        processed: UInt64
    ) {
        guard let cachedAndWritten = cachedInput.checkedAdding(cacheWrite), cachedAndWritten <= input,
            reasoningOutput <= output
        else {
            return nil
        }
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
        self.processed = processed
    }

    var uncachedInput: UInt64 {
        input - cachedInput - cacheWrite
    }

    fileprivate init(_ value: JSONValue) throws {
        let (input, cachedInput, cacheWrite, output, reasoningOutput, processed) = try value.fields(
            .uint64("input_tokens"),
            .uint64("cached_input_tokens"),
            .uint64("cache_write_input_tokens"),
            .uint64("output_tokens"),
            .uint64("reasoning_output_tokens"),
            .uint64("total_tokens")
        )
        guard let input, let cachedInput, let output, let reasoningOutput, let processed,
            let usage = CodexTokenUsage(
                input: input,
                cachedInput: cachedInput,
                cacheWrite: cacheWrite ?? 0,
                output: output,
                reasoningOutput: reasoningOutput,
                processed: processed
            )
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
