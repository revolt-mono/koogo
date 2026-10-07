import Foundation

/// Reads the `turn_completed` updates that Grok appends to each session's `updates.jsonl`. Each one sums a whole prompt per model, subagents included.
struct GrokUsageLogParser: UsageLogParser {
    private var promptIndex: UInt64?
    /// Billed turns of the surviving branch by prompt. A rewind abandons later prompts, which stay billed but no longer match the rewritten response history.
    private(set) var promptTurns: [UInt64: UsageEventID] = [:]

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        do {
            guard let record = JSONValue(object: line), let params = try record.fields(.value("params")) else {
                return nil
            }
            let (update, meta) = try params.fields(.value("update"), .value("_meta"))
            guard let update else {
                return nil
            }
            let (kind, updateMeta, rewindTarget, usage) = try update.fields(
                .value("sessionUpdate"),
                .value("_meta"),
                .value("target_prompt_index"),
                .value("usage")
            )
            guard let kind else {
                return nil
            }
            switch kind {
            case "user_message_chunk":
                if let index = try updateMeta?.fields(.uint64("promptIndex")) {
                    promptIndex = index
                }
            case "rewind_marker":
                promptIndex = nil
                guard let target = try? rewindTarget?.integer(UInt64.self) else {
                    promptTurns.removeAll()
                    throw MalformedUsageRecord()
                }
                promptTurns = promptTurns.filter { $0.key < target }
            case "turn_completed":
                defer { promptIndex = nil }
                guard let usage = usage?.nonNull else {
                    return nil
                }
                let outcome = try Self.completedTurn(GrokPromptUsage(usage), meta: meta)
                if case .event(let event) = outcome, let promptIndex {
                    promptTurns[promptIndex] = event.id
                }
                return outcome
            default: break
            }
            return nil
        } catch {
            promptIndex = nil
            throw error
        }
    }

    private static func completedTurn(_ usage: GrokPromptUsage, meta: JSONValue?) throws -> UsageLineOutcome? {
        guard let meta else {
            throw MalformedUsageRecord()
        }
        let (eventID, milliseconds) = try meta.fields(.string("eventId"), .uint64("agentTimestampMs"))
        guard let eventID, let milliseconds else {
            throw MalformedUsageRecord()
        }
        let timestamp = Date(unixMilliseconds: milliseconds)
        guard let primaryModel = usage.primaryModel else {
            // A cancelled prompt completes with no model rows and nothing billed.
            guard usage.totalTokens == 0 else { throw MalformedUsageRecord() }
            return nil
        }
        var quotes: [String: UsageQuote] = [:]
        for (model, tokens) in usage.modelUsage.sorted(by: { $0.key < $1.key }) {
            guard let quote = GrokUsagePricing.quote(model: model, tokens: tokens) else {
                return .unpricedModel(id: model, timestamp: timestamp)
            }
            quotes[model] = quote
        }

        return .event(
            UsageEvent(
                id: .grok(eventID: eventID, timestampMilliseconds: milliseconds),
                record: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.totalTokens,
                    costUSD: quotes.values.map(\.costUSD).reduce(0, +),
                    modelTurn: .init(model: ModelID(primaryModel), reasoningEffort: nil)
                )
            )
        )
    }
}

private struct GrokPromptUsage {
    /// Full prompt input, cache reads included, plus output.
    let totalTokens: UInt64
    let modelUsage: [String: GrokTokenUsage]

    init(_ value: JSONValue) throws {
        let (totalTokens, modelUsage) = try value.fields(.uint64("totalTokens"), .value("modelUsage"))
        guard let totalTokens, var models = try modelUsage?.object() else {
            throw MalformedUsageRecord()
        }
        var usageByModel: [String: GrokTokenUsage] = [:]
        while let model = try models.next() {
            guard let name = try model.key.string() else {
                throw MalformedUsageRecord()
            }
            usageByModel[name] = try GrokTokenUsage(model.value)
        }
        self.totalTokens = totalTokens
        self.modelUsage = usageByModel
    }

    var primaryModel: String? {
        modelUsage.max { lhs, rhs in
            (lhs.value.modelCalls, rhs.key) < (rhs.value.modelCalls, lhs.key)
        }?.key
    }
}

struct GrokTokenUsage: Sendable {
    /// Full prompt input, cache reads included.
    let input: UInt64
    let cachedInput: UInt64
    let output: UInt64
    let modelCalls: UInt64

    init?(input: UInt64, cachedInput: UInt64, output: UInt64, modelCalls: UInt64) {
        guard cachedInput <= input else {
            return nil
        }
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.modelCalls = modelCalls
    }

    var uncachedInput: UInt64 {
        input - cachedInput
    }

    fileprivate init(_ value: JSONValue) throws {
        let (input, cachedInput, output, modelCalls) = try value.fields(
            .uint64("inputTokens"),
            .uint64("cachedReadTokens"),
            .uint64("outputTokens"),
            .uint64("modelCalls")
        )
        guard let input, let cachedInput, let output, let modelCalls,
            let usage = GrokTokenUsage(input: input, cachedInput: cachedInput, output: output, modelCalls: modelCalls)
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
