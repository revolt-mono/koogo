import Foundation

/// codex writes one `token_usage_record` per completed response; the preceding `turn_context` names the model.
struct CodexUsageLogParser: UsageLogParser {
    private var model: ModelID?

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var kind: JSONValue?
        var timestamp: JSONValue?
        var payload: JSONValue?
        while let member = try record.next() {
            switch member.key {
            case "type":
                guard member.value.isString("turn_context") || member.value.isString("token_usage_record") else {
                    return nil
                }
                kind = member.value
            case "timestamp": timestamp = member.value
            case "payload": payload = member.value
            default: break
            }
        }
        switch kind {
        case nil:
            return nil
        case "turn_context"?:
            model = try? payload?.member("model")?.string()?.nonEmpty.map(ModelID.init(_:))
            guard model != nil else {
                throw MalformedUsageRecord()
            }
            return nil
        default:
            guard let payload, let timestamp = try timestamp?.text().flatMap(Date.init(iso8601:)) else {
                throw MalformedUsageRecord()
            }
            let record = try CodexTokenUsageRecord(payload)
            guard let model else {
                return nil
            }
            guard let quote = CodexUsagePricing.quote(model: model, tokens: record.usage) else {
                return .unpricedModel(model, timestamp: timestamp)
            }
            return .event(
                UsageEvent(
                    id: .codex(turnID: record.turnID, cumulativeTotal: record.threadTotal),
                    record: UsageRecord(
                        timestamp: timestamp,
                        processedTokens: record.usage.processed,
                        cost: quote.cost,
                        model: quote.model
                    )
                )
            )
        }
    }
}

private struct CodexTokenUsageRecord {
    let turnID: JSONText
    let usage: CodexTokenUsage
    let threadTotal: UInt64

    init(_ payload: JSONValue) throws {
        var turnID: JSONValue?
        var usage: JSONValue?
        var threadUsage: JSONValue?
        var fields = try payload.object()
        while let member = try fields.next() {
            switch member.key {
            case "turn_id": turnID = member.value
            case "usage": usage = member.value
            case "thread_token_usage": threadUsage = member.value
            default: break
            }
        }
        guard let turnID = try turnID?.text(), let usage = try usage.map(CodexTokenUsage.init),
            let threadTotal = try threadUsage?.member("total_tokens")?.uint64()
        else {
            throw MalformedUsageRecord()
        }
        self.turnID = turnID
        self.usage = usage
        self.threadTotal = threadTotal
    }
}

struct CodexTokenUsage: Sendable {
    let input: UInt64
    let cachedInput: UInt64
    let cacheWrite: UInt64
    let output: UInt64
    let processed: UInt64

    init?(input: UInt64, cachedInput: UInt64, cacheWrite: UInt64, output: UInt64, processed: UInt64) {
        guard let cachedAndWritten = cachedInput.checkedAdding(cacheWrite), cachedAndWritten <= input else {
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
        var input: JSONValue?
        var cachedInput: JSONValue?
        var cacheWrite: JSONValue?
        var output: JSONValue?
        var processed: JSONValue?
        var fields = try value.object()
        while let member = try fields.next() {
            switch member.key {
            case "input_tokens": input = member.value
            case "cached_input_tokens": cachedInput = member.value
            case "cache_write_input_tokens": cacheWrite = member.value
            case "output_tokens": output = member.value
            case "total_tokens": processed = member.value
            default: break
            }
        }
        guard let input = try input?.uint64(), let cachedInput = try cachedInput?.uint64(),
            let output = try output?.uint64(), let processed = try processed?.uint64(),
            let usage = CodexTokenUsage(
                input: input,
                cachedInput: cachedInput,
                cacheWrite: try cacheWrite?.uint64() ?? 0,
                output: output,
                processed: processed
            )
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
