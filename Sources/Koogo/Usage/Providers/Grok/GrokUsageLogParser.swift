import Foundation

private enum GrokUpdateKind: String, LogRecordKind {
    case turnCompleted = "turn_completed"
    case other
}

/// Reads the `turn_completed` updates that Grok appends to each session's `updates.jsonl`.
/// Each one sums a whole prompt per model, subagents included.
struct GrokLogParser: UsageLogParser {
    private static let eventMarkers = [
        GrokUpdateKind.turnCompleted.jsonStringMarker,
        GrokLogRecord.Update.usageMarker,
    ]

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

    func mayContainEvent(_ line: UnsafeRawBufferPointer) -> Bool {
        Self.eventMarkers.allSatisfy { line.contains($0) }
    }

    func parse(_ line: Data, decoder: JSONDecoder) -> UsageLineOutcome? {
        guard
            let record = try? decoder.decode(GrokLogRecord.self, from: line),
            record.params.update.kind == .turnCompleted,
            let usage = record.params.update.usage
        else {
            return nil
        }
        let meta = record.params.meta
        let timestamp = Date(timeIntervalSince1970: TimeInterval(meta.agentTimestampMilliseconds) / 1_000)
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
            .grok(
                id: UsageEvent.GrokID(eventID: meta.eventID, timestamp: timestamp),
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

private struct GrokLogRecord: Decodable {
    struct Params: Decodable {
        let update: Update
        let meta: Meta

        private enum CodingKeys: String, CodingKey {
            case update
            case meta = "_meta"
        }
    }

    struct Update: Decodable {
        static let usageMarker = Data("\"\(CodingKeys.usage.rawValue)\"".utf8)

        let kind: GrokUpdateKind
        let usage: GrokPromptUsage?

        private enum CodingKeys: String, CodingKey {
            case kind = "sessionUpdate"
            case usage
        }
    }

    struct Meta: Decodable {
        let eventID: String
        let agentTimestampMilliseconds: UInt64

        private enum CodingKeys: String, CodingKey {
            case eventID = "eventId"
            case agentTimestampMilliseconds = "agentTimestampMs"
        }
    }

    let params: Params
}

private struct GrokPromptUsage: Decodable {
    /// Full prompt input, cache reads included, plus output.
    let totalTokens: UInt64
    let modelUsage: [String: GrokTokenUsage]

    /// The model with the most calls, as Grok itself ranks them.
    var primaryModel: String? {
        modelUsage.max { lhs, rhs in
            (lhs.value.modelCalls, rhs.key) < (rhs.value.modelCalls, lhs.key)
        }?.key
    }
}

extension GrokTokenUsage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case input = "inputTokens"
        case cachedInput = "cachedReadTokens"
        case output = "outputTokens"
        case modelCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard
            let usage = GrokTokenUsage(
                input: try container.decode(UInt64.self, forKey: .input),
                cachedInput: try container.decode(UInt64.self, forKey: .cachedInput),
                output: try container.decode(UInt64.self, forKey: .output),
                modelCalls: try container.decode(UInt64.self, forKey: .modelCalls)
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .cachedInput,
                in: container,
                debugDescription: "invalid token usage"
            )
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
