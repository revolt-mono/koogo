import Foundation

/// Reads the `turn_completed` updates that Grok appends to each session's `updates.jsonl`.
/// Each one sums a whole prompt per model, subagents included.
struct GrokLogParser: UsageLogParser {
    /// Only top-level session updates count: a subagent session's usage is already folded
    /// into the parent turn that spawned it. A session without a readable summary yet is
    /// retried on the next scan.
    static func isUsageLog(_ url: URL) -> Bool {
        let summaryURL = url.deletingLastPathComponent().appending(path: "summary.json")
        guard
            url.lastPathComponent == "updates.jsonl",
            let data = try? Data(contentsOf: summaryURL),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data)
        else {
            return false
        }
        return summary.kind?.hasPrefix("subagent") != true
    }

    func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        guard var record = JSONObjectReader(line) else {
            return nil
        }
        var params: JSONValue?
        while let member = try record.next() {
            if case "params" = member.key {
                params = member.value
            }
        }
        guard let params,
            let update = try params.member("update"),
            try update.member("sessionUpdate")?.isString("turn_completed") == true,
            let loggedUsage = try update.member("usage")?.nonNull
        else {
            return nil
        }
        let usage = try GrokPromptUsage(loggedUsage)
        guard let meta = try params.member("_meta"),
            let eventID = try meta.member("eventId")?.string(),
            let milliseconds = try meta.member("agentTimestampMs")?.integer(UInt64.self)
        else {
            throw MalformedUsageRecord()
        }
        let timestamp = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        var quotes: [String: UsageQuote] = [:]
        for (model, tokens) in usage.modelUsage.sorted(by: { $0.key < $1.key }) {
            guard let quote = GrokUsagePricing.quote(model: model, tokens: tokens) else {
                return .unpricedModel(id: model, timestamp: timestamp)
            }
            quotes[model] = quote
        }
        guard let primaryModel = usage.primaryModel, let primaryQuote = quotes[primaryModel] else {
            return nil
        }

        return .event(
            UsageEvent(
                key: .grok(eventID: eventID, timestamp: timestamp),
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.totalTokens,
                    costUSD: quotes.values.map(\.costUSD).reduce(0, +),
                    modelTurn: UsageRecord.ModelTurn(model: primaryQuote.model, reasoningEffort: nil)
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

    /// The model with the most calls, as Grok itself ranks them.
    var primaryModel: String? {
        modelUsage.max { lhs, rhs in
            (lhs.value.modelCalls, rhs.key) < (rhs.value.modelCalls, lhs.key)
        }?.key
    }
}

extension GrokTokenUsage {
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

private struct GrokSessionSummary: Decodable {
    let kind: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "session_kind"
    }
}
