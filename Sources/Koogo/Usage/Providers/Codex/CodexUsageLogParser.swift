import Foundation

/// codex writes one `token_usage_record` per completed response; the preceding `turn_context` names the model.
struct CodexUsageLogParser: UsageLogParser {
    private var model: ModelID?

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let object = JSONValue(object: line) else {
            return nil
        }
        let (kind, timestamp, payload) = try object.fields(
            .kind("type") { $0.isString("turn_context") || $0.isString("token_usage_record") },
            .value("timestamp"),
            .value("payload")
        )
        guard let kind else {
            return nil
        }
        switch kind {
        case "turn_context":
            model = try? payload?.fields(.string("model"))?.nonEmpty.map(ModelID.init(_:))
            guard model != nil else {
                throw MalformedUsageRecord()
            }
            return nil
        default:
            let record = try CodexTokenUsageRecord(payload: payload, timestamp: timestamp)
            guard let model else {
                return nil
            }
            guard let quote = CodexUsagePricing.quote(model: model, tokens: record.usage) else {
                return .unpricedModel(model, timestamp: record.timestamp)
            }
            return .event(
                UsageEvent(
                    id: .codex(turnID: record.turnID, cumulativeTotal: record.threadTotal),
                    record: UsageRecord(
                        timestamp: record.timestamp,
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
    let turnID: String
    let usage: CodexTokenUsage
    let threadTotal: UInt64
    let timestamp: Date

    init(payload: JSONValue?, timestamp: JSONValue?) throws {
        guard let payload, let logged = try timestamp?.string(), let timestamp = Date(iso8601: logged) else {
            throw MalformedUsageRecord()
        }
        let (turnID, usage, threadTotal) = try payload.fields(
            .string("turn_id"),
            JSONField("usage", CodexTokenUsage.init(_:)),
            JSONField("thread_token_usage") { try $0.fields(.uint64("total_tokens")) }
        )
        guard let turnID, let usage, let threadTotal else {
            throw MalformedUsageRecord()
        }
        self.turnID = turnID
        self.usage = usage
        self.threadTotal = threadTotal
        self.timestamp = timestamp
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
        let (input, cachedInput, cacheWrite, output, processed) = try value.fields(
            .uint64("input_tokens"),
            .uint64("cached_input_tokens"),
            .uint64("cache_write_input_tokens"),
            .uint64("output_tokens"),
            .uint64("total_tokens")
        )
        guard let input, let cachedInput, let output, let processed,
            let usage = CodexTokenUsage(
                input: input,
                cachedInput: cachedInput,
                cacheWrite: cacheWrite ?? 0,
                output: output,
                processed: processed
            )
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
