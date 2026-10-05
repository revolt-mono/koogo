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

private enum CodexRecord {
    case turnContext(payload: JSONValue)
    case eventMessage(payload: JSONValue, timestamp: JSONValue?)

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var isTurnContext: Bool?
        var timestamp: JSONValue?
        var payload: JSONValue?
        while let member = try record.next() {
            switch member.key {
            case "type":
                switch member.value {
                case "turn_context": isTurnContext = true
                case "event_msg": isTurnContext = false
                default: return nil
                }
            case "timestamp": timestamp = member.value
            case "payload": payload = member.value
            default: continue
            }
        }
        guard let isTurnContext else {
            return nil
        }
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
        var payload = try payload.object()
        var id: String?
        var model: String?
        var reasoningEffort: String?
        while let member = try payload.next() {
            switch member.key {
            case "turn_id": id = try member.value.string()
            case "model": model = try member.value.string()
            case "effort": reasoningEffort = try member.value.string()
            default: continue
            }
        }
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
        var payload = try payload.object()
        var isTokenCount = false
        var info: JSONValue?
        while let member = try payload.next() {
            switch member.key {
            case "type":
                guard member.value.isString("token_count") else {
                    return nil
                }
                isTokenCount = true
            case "info": info = member.value
            default: continue
            }
        }
        guard isTokenCount, var info = try info?.nonNull?.object() else {
            return nil
        }
        var last: CodexTokenUsage?
        var total: CodexTokenUsage?
        while let member = try info.next() {
            switch member.key {
            case "last_token_usage": last = try CodexTokenUsage(member.value)
            case "total_token_usage": total = try CodexTokenUsage(member.value)
            case "model_context_window": _ = try member.value.integer(Int64.self)
            default: continue
            }
        }
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
        let (cachedAndWritten, overflow) = cachedInput.addingReportingOverflow(cacheWrite)
        guard !overflow, cachedAndWritten <= input, reasoningOutput <= output else {
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
        var usage = try value.object()
        var input: UInt64?
        var cachedInput: UInt64?
        var cacheWrite: UInt64?
        var output: UInt64?
        var reasoningOutput: UInt64?
        var processed: UInt64?
        while let member = try usage.next() {
            switch member.key {
            case "input_tokens": input = try member.value.integer()
            case "cached_input_tokens": cachedInput = try member.value.integer()
            case "cache_write_input_tokens": cacheWrite = try member.value.integer()
            case "output_tokens": output = try member.value.integer()
            case "reasoning_output_tokens": reasoningOutput = try member.value.integer()
            case "total_tokens": processed = try member.value.integer()
            default: continue
            }
        }
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
