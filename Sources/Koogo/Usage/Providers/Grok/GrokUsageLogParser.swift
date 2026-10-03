import Foundation

/// Reads the `turn_completed` updates that Grok appends to each session's `updates.jsonl`.
/// Each one sums a whole prompt per model, subagents included.
struct GrokLogParser: UsageLogParser {
    private var promptIndex: UInt64?
    /// Billed turns of the surviving branch by prompt. A rewind abandons later prompts, which stay billed
    /// but no longer match the rewritten response history.
    private(set) var promptTurns: [UInt64: UsageEventID] = [:]

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        do {
            guard JSONObjectReader(line) != nil,
                let params = try JSONValue(bytes: line).member("params"),
                let update = try params.member("update"),
                let kind = try update.member("sessionUpdate")
            else {
                return nil
            }
            switch kind {
            case "user_message_chunk":
                if let index = try update.member("_meta")?.member("promptIndex")?.integer(UInt64.self) {
                    promptIndex = index
                }
            case "rewind_marker":
                promptIndex = nil
                guard let target = try? update.member("target_prompt_index")?.integer(UInt64.self) else {
                    promptTurns.removeAll()
                    throw MalformedUsageRecord()
                }
                promptTurns = promptTurns.filter { $0.key < target }
            case "turn_completed":
                defer { promptIndex = nil }
                guard let usage = try update.member("usage")?.nonNull else {
                    return nil
                }
                let outcome = try Self.completedTurn(GrokPromptUsage(usage), params: params)
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

    private static func completedTurn(_ usage: GrokPromptUsage, params: JSONValue) throws -> UsageLineOutcome? {
        guard let meta = try params.member("_meta"),
            let eventID = try meta.member("eventId")?.string(),
            let milliseconds = try meta.member("agentTimestampMs")?.integer(UInt64.self)
        else {
            throw MalformedUsageRecord()
        }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
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
        var usage = try value.object()
        var totalTokens: UInt64?
        var modelUsage: [String: GrokTokenUsage]?
        while let member = try usage.next() {
            switch member.key {
            case "totalTokens": totalTokens = try member.value.integer()
            case "modelUsage":
                var models = try member.value.object()
                var usageByModel: [String: GrokTokenUsage] = [:]
                while let model = try models.next() {
                    guard let name = try model.key.string() else {
                        throw MalformedUsageRecord()
                    }
                    usageByModel[name] = try GrokTokenUsage(model.value)
                }
                modelUsage = usageByModel
            default: continue
            }
        }
        guard let totalTokens, let modelUsage else {
            throw MalformedUsageRecord()
        }
        self.totalTokens = totalTokens
        self.modelUsage = modelUsage
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
        var usage = try value.object()
        var input: UInt64?
        var cachedInput: UInt64?
        var output: UInt64?
        var modelCalls: UInt64?
        while let member = try usage.next() {
            switch member.key {
            case "inputTokens": input = try member.value.integer()
            case "cachedReadTokens": cachedInput = try member.value.integer()
            case "outputTokens": output = try member.value.integer()
            case "modelCalls": modelCalls = try member.value.integer()
            default: continue
            }
        }
        guard let input, let cachedInput, let output, let modelCalls,
            let usage = GrokTokenUsage(input: input, cachedInput: cachedInput, output: output, modelCalls: modelCalls)
        else {
            throw MalformedUsageRecord()
        }
        self = usage
    }
}
