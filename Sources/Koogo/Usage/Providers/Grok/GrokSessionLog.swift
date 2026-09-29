import Foundation

/// A top-level Grok session: `updates.jsonl` bills each prompt, and `chat_history.jsonl`, when present,
/// records the reasoning effort applied to each response of the surviving branch.
struct GrokSessionLog: UsageLog {
    private var updates: UsageLogFile<ParsedUsage<GrokLogParser>>
    private var history: UsageLogFile<GrokChatHistory>?
    private let historyURL: URL
    private(set) var events: UsageEventIndex

    /// Admits `updates.jsonl` once its session has a readable summary. A subagent session is skipped,
    /// since the parent turn that spawned it already includes its usage.
    init?(_ url: URL, since historyStart: Date) {
        let sessionURL = url.deletingLastPathComponent()
        guard url.lastPathComponent == "updates.jsonl",
            let data = try? Data(contentsOf: sessionURL.appending(path: "summary.json")),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data),
            summary.kind?.hasPrefix("subagent") != true,
            let updates = UsageLogFile(url, lines: ParsedUsage<GrokLogParser>(since: historyStart))
        else {
            return nil
        }
        let historyURL = sessionURL.appending(path: "chat_history.jsonl")
        let history = UsageLogFile(historyURL, lines: GrokChatHistory())
        self.updates = updates
        self.history = history
        self.historyURL = historyURL
        events = Self.join(updates.lines, history: history?.lines)
    }

    var malformedLines: Int {
        updates.malformedLines + (history?.malformedLines ?? 0)
    }

    mutating func refresh(observed metadata: UsageFileMetadata) -> Bool {
        let updatesChanged = updates.refresh(observed: metadata)
        let historyChanged = refreshHistory()
        guard updatesChanged || historyChanged else {
            return false
        }
        events = Self.join(updates.lines, history: history?.lines)
        return true
    }

    mutating func discard(before historyStart: Date) {
        updates.discard(before: historyStart)
        events.discard(before: historyStart)
    }

    /// History can change while billed updates stay put, so every pass checks it.
    private mutating func refreshHistory() -> Bool {
        guard let metadata = UsageFileMetadata(path: historyURL.path) else {
            let removed = history != nil
            history = nil
            return removed
        }
        if let changed = history?.refresh(observed: metadata) {
            return changed
        }
        history = UsageLogFile(historyURL, lines: GrokChatHistory())
        return history != nil
    }

    /// Tags each surviving prompt's billed turn with the effort its responses used most on the billed model.
    /// The tagged copy outranks untagged copies of the same turn, here and in forks without history.
    private static func join(_ updates: ParsedUsage<GrokLogParser>, history: GrokChatHistory?) -> UsageEventIndex {
        var events = updates.events
        guard let history else {
            return events
        }
        for (promptIndex, event) in updates.parser.promptTurns {
            guard let turn = event.usage.modelTurn, case .named(let model, _) = turn.model,
                let effort = history.effort(promptIndex: promptIndex, model: model)
            else {
                continue
            }
            let usage = UsageRecord(
                timestamp: event.usage.timestamp,
                processedTokens: event.usage.processedTokens,
                costUSD: event.usage.costUSD,
                modelTurn: .init(model: turn.model, reasoningEffort: effort)
            )
            events.insert(
                .event(
                    UsageEvent(key: event.key, usage: usage, revision: .init(outputTokens: 0, metadataCompleteness: 1))
                )
            )
        }
        return events
    }
}

/// Reasoning effort votes per prompt and model from the responses in `chat_history.jsonl`.
struct GrokChatHistory: UsageLogLines {
    private var promptIndex: UInt64?
    private var votes: [UInt64: [String: [String: Int]]] = [:]

    mutating func consume(_ line: UnsafeRawBufferPointer) throws {
        do {
            guard JSONObjectReader(line) != nil else {
                return
            }
            let record = JSONValue(bytes: line)
            guard let kind = try record.member("type") else {
                return
            }
            switch kind {
            case "user":
                if let index = try record.member("prompt_index")?.integer(UInt64.self) {
                    promptIndex = index
                }
            case "assistant":
                guard let promptIndex,
                    let model = try record.member("model_id")?.string(), !model.isEmpty,
                    let effort = try record.member("reasoning_effort")?.string(), !effort.isEmpty
                else {
                    return
                }
                votes[promptIndex, default: [:]][model, default: [:]][effort, default: 0] += 1
            default: break
            }
        } catch {
            promptIndex = nil
            throw error
        }
    }

    func restarted() -> Self {
        Self()
    }

    /// The effort most responses to the prompt used on `model`.
    func effort(promptIndex: UInt64, model: String) -> String? {
        votes[promptIndex]?[model]?.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }
}

private struct GrokSessionSummary: Decodable {
    let kind: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "session_kind"
    }
}
