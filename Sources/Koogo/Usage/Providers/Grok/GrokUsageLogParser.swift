import Foundation

/// Reads the `turn_completed` updates that Grok appends to each session's `updates.jsonl`.
/// Each one sums a whole prompt per model, subagents included.
struct GrokLogParser: UsageLogParser {
    private var promptIndex: UInt64?
    private var promptIndices: [UsageEvent.Key: UInt64] = [:]

    /// admits updates and response history for top-level sessions; parent usage already includes subagents.
    static func isUsageLog(_ url: URL) -> Bool {
        let sessionURL = url.deletingLastPathComponent()
        let summaryURL = sessionURL.appending(path: "summary.json")
        guard
            url.lastPathComponent == "updates.jsonl"
                || (url.lastPathComponent == "chat_history.jsonl"
                    && FileManager.default.fileExists(atPath: sessionURL.appending(path: "updates.jsonl").path)),
            let data = try? Data(contentsOf: summaryURL),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data)
        else {
            return false
        }
        return summary.kind?.hasPrefix("subagent") != true
    }

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
                    promptIndices.removeAll()
                    throw MalformedUsageRecord()
                }
                // the abandoned branch stays billed, but current history only describes surviving prompts.
                promptIndices = promptIndices.filter { $0.value < target }
            case "turn_completed":
                defer { promptIndex = nil }
                if let usage = try update.member("usage")?.nonNull {
                    return try completedTurn(GrokPromptUsage(usage), params: params)
                }
            default: break
            }
            return nil
        } catch {
            promptIndex = nil
            throw error
        }
    }

    /// merges response effort while preserving raw billed records for later history rewrites or removal.
    func merge(_ events: UsageEventIndex, history: GrokHistoryLogParser?, into merged: inout UsageEventIndex) {
        merged.merge(events)
        guard let history else {
            return
        }
        for event in events.values {
            guard let index = promptIndices[event.key], let turn = event.usage.modelTurn,
                case .named(let model, _) = turn.model,
                let effort = history.effort(for: index, model: model)
            else {
                continue
            }
            var usage = event.usage
            usage.modelTurn = .init(model: turn.model, reasoningEffort: effort)
            merged.insert(
                .event(
                    UsageEvent(
                        key: event.key,
                        usage: usage,
                        revision: .init(outputTokens: 0, metadataCompleteness: 1)
                    )
                )
            )
        }
    }

    private mutating func completedTurn(_ usage: GrokPromptUsage, params: JSONValue) throws -> UsageLineOutcome? {
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

        let key = UsageEvent.Key.grok(eventID: eventID, timestamp: timestamp)
        if let promptIndex {
            promptIndices[key] = promptIndex
        }
        return .event(
            UsageEvent(
                key: key,
                usage: UsageRecord(
                    timestamp: timestamp,
                    processedTokens: usage.totalTokens,
                    costUSD: quotes.values.map(\.costUSD).reduce(0, +),
                    modelTurn: .init(model: primaryQuote.model, reasoningEffort: nil)
                ),
                revision: .init(outputTokens: 0, metadataCompleteness: 0)
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
