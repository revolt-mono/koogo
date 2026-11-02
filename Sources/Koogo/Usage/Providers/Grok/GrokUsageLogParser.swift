import Foundation

/// each completed grok turn sums the whole prompt per model, including subagents.
struct GrokUsageLogParser: UsageLogParser {
    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard let turn = try GrokCompletedTurn(line) else {
            return nil
        }
        let timestamp = Date(unixMilliseconds: turn.milliseconds)
        let prompt = try GrokPromptUsage(turn.usage)
        guard let primaryModel = prompt.primaryModel else {
            // cancelled grok prompts can complete with no model rows and zero billable tokens.
            guard prompt.totalTokens == 0 else { throw MalformedUsageRecord() }
            return nil
        }
        var cost = Picodollars.zero
        for (model, tokens) in prompt.modelUsage {
            guard let modelCost = GrokUsagePricing.cost(of: tokens, model: model) else {
                return .unpricedModel(model, timestamp: timestamp)
            }
            cost += modelCost
        }

        return .event(
            UsageEvent(
                id: .grok(eventID: turn.eventID, timestampMilliseconds: turn.milliseconds),
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

/// a session update that completed a turn with usage; other lines read as nil.
private struct GrokCompletedTurn {
    let usage: JSONValue
    let eventID: JSONText
    let milliseconds: UInt64

    init?(_ line: UnsafeRawBufferPointer) throws {
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var params: JSONValue?
        while let member = try record.next() {
            if member.key.isString("params") {
                params = member.value
            }
        }
        guard let update = try params?.member("update"), let usage = try Self.completedTurnUsage(in: update) else {
            return nil
        }
        guard let meta = try params?.member("_meta"), let eventID = try meta.member("eventId")?.text(),
            let milliseconds = try meta.member("agentTimestampMs")?.uint64()
        else {
            throw MalformedUsageRecord()
        }
        self.usage = usage
        self.eventID = eventID
        self.milliseconds = milliseconds
    }

    private static func completedTurnUsage(in update: JSONValue) throws -> JSONValue? {
        var isCompletedTurn = false
        var usage: JSONValue?
        var fields = try update.object()
        while let member = try fields.next() {
            switch member.key {
            case "sessionUpdate":
                guard member.value.isString("turn_completed") else {
                    return nil
                }
                isCompletedTurn = true
            case "usage": usage = member.value
            default: break
            }
        }
        return isCompletedTurn ? usage?.nonNull : nil
    }
}

private struct GrokPromptUsage {
    /// prompt input including cache reads, plus output.
    let totalTokens: UInt64
    let modelUsage: [(model: ModelID, tokens: GrokTokenUsage)]

    init(_ value: JSONValue) throws {
        var totalTokens: JSONValue?
        var modelUsage: JSONValue?
        var fields = try value.object()
        while let member = try fields.next() {
            switch member.key {
            case "totalTokens": totalTokens = member.value
            case "modelUsage": modelUsage = member.value
            default: break
            }
        }
        guard let totalTokens = try totalTokens?.uint64() else {
            throw MalformedUsageRecord()
        }
        var models = try modelUsage?.object()
        var usage: [(model: ModelID, tokens: GrokTokenUsage)] = []
        while let row = try models?.next() {
            guard let name = try row.key.string() else {
                throw MalformedUsageRecord()
            }
            usage.append((ModelID(name), try GrokTokenUsage(row.value)))
        }
        self.totalTokens = totalTokens
        self.modelUsage = usage
    }

    /// grok's rule: most calls, then most tokens; remaining ties go to the first name.
    var primaryModel: ModelID? {
        modelUsage.max { lhs, rhs in
            (lhs.tokens.modelCalls, lhs.tokens.totalTokens, rhs.model)
                < (rhs.tokens.modelCalls, rhs.tokens.totalTokens, lhs.model)
        }?.model
    }
}

struct GrokTokenUsage: Sendable {
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

    var totalTokens: UInt64 {
        input.saturatingAdding(output)
    }

    fileprivate init(_ value: JSONValue) throws {
        var input: JSONValue?
        var cachedInput: JSONValue?
        var output: JSONValue?
        var modelCalls: JSONValue?
        var fields = try value.object()
        while let member = try fields.next() {
            switch member.key {
            case "inputTokens": input = member.value
            case "cachedReadTokens": cachedInput = member.value
            case "outputTokens": output = member.value
            case "modelCalls": modelCalls = member.value
            default: break
            }
        }
        guard let input = try input?.uint64(), let cachedInput = try cachedInput?.uint64(),
            let output = try output?.uint64(), let modelCalls = try modelCalls?.uint64(),
            let usage = GrokTokenUsage(input: input, cachedInput: cachedInput, output: output, modelCalls: modelCalls)
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
