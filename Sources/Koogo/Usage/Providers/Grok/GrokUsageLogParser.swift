import Foundation

/// each completed grok turn sums the whole prompt per model, including subagents.
struct GrokUsageLogParser: UsageLogParser {
    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let record = JSONValue(object: line), let params = try record.fields(.value("params")) else {
            return nil
        }
        let (update, meta) = try params.fields(.value("update"), .value("_meta"))
        guard let update else {
            return nil
        }
        let (kind, usage) = try update.fields(.kind("sessionUpdate") { $0.isString("turn_completed") }, .value("usage"))
        guard kind != nil, let usage = usage?.nonNull else {
            return nil
        }
        guard let meta else {
            throw MalformedUsageRecord()
        }
        let (eventID, milliseconds) = try meta.fields(.string("eventId"), .uint64("agentTimestampMs"))
        guard let eventID, let milliseconds else {
            throw MalformedUsageRecord()
        }
        let timestamp = Date(unixMilliseconds: milliseconds)
        let prompt = try GrokPromptUsage(usage)
        guard let primaryModel = prompt.primaryModel else {
            // cancelled grok prompts can complete with no model rows and zero billable tokens.
            guard prompt.totalTokens == 0 else { throw MalformedUsageRecord() }
            return nil
        }
        var cost = Picodollars.zero
        for (model, tokens) in prompt.modelUsage.sorted(by: { $0.key < $1.key }) {
            guard let modelCost = GrokUsagePricing.cost(of: tokens, model: model) else {
                return .unpricedModel(model, timestamp: timestamp)
            }
            cost += modelCost
        }

        return .event(
            UsageEvent(
                id: .grok(eventID: eventID, timestampMilliseconds: milliseconds),
                record: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: prompt.totalTokens,
                    cost: cost,
                    model: primaryModel
                )
            )
        )
    }
}

private struct GrokPromptUsage {
    /// prompt input including cache reads, plus output.
    let totalTokens: UInt64
    let modelUsage: [ModelID: GrokTokenUsage]

    init(_ value: JSONValue) throws {
        let (totalTokens, modelUsage) = try value.fields(.uint64("totalTokens"), .value("modelUsage"))
        guard let totalTokens, var models = try modelUsage?.object() else {
            throw MalformedUsageRecord()
        }
        var usageByModel: [ModelID: GrokTokenUsage] = [:]
        while let model = try models.next() {
            guard let name = try model.key.string() else {
                throw MalformedUsageRecord()
            }
            usageByModel[ModelID(name)] = try GrokTokenUsage(model.value)
        }
        self.totalTokens = totalTokens
        self.modelUsage = usageByModel
    }

    var primaryModel: ModelID? {
        modelUsage.max { lhs, rhs in
            (lhs.value.modelCalls, rhs.key) < (rhs.value.modelCalls, lhs.key)
        }?.key
    }
}

struct GrokTokenUsage: Sendable {
    /// prompt input including cache reads.
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
