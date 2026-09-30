import Foundation

struct GrokSessionLog: UsageLog {
    private var updates: UsageLogFile<GrokLogParser>
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
            let updates = UsageLogFile(url, parser: GrokLogParser(), since: historyStart)
        else {
            return nil
        }
        let historyURL = sessionURL.appending(path: "chat_history.jsonl")
        let history = Self.openHistory(historyURL)
        self.updates = updates
        self.history = history
        self.historyURL = historyURL
        events = Self.join(updates, history: history?.parser)
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
        events = Self.join(updates, history: history?.parser)
        return true
    }

    mutating func discard(before historyStart: Date) {
        updates.discard(before: historyStart)
        events.discard(before: historyStart)
    }

    private mutating func refreshHistory() -> Bool {
        guard let metadata = UsageFileMetadata(path: historyURL.path) else {
            let removed = history != nil
            history = nil
            return removed
        }
        if let changed = history?.refresh(observed: metadata) {
            return changed
        }
        history = Self.openHistory(historyURL)
        return history != nil
    }

    private static func openHistory(_ url: URL) -> UsageLogFile<GrokChatHistory>? {
        UsageLogFile(url, parser: GrokChatHistory(), since: .distantPast)
    }

    private static func join(_ updates: UsageLogFile<GrokLogParser>, history: GrokChatHistory?) -> UsageEventIndex {
        var events = updates.events
        guard let history else {
            return events
        }
        for (promptIndex, event) in updates.parser.promptTurns {
            guard let turn = event.usage.modelTurn,
                let effort = history.effort(promptIndex: promptIndex, model: turn.model.id)
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

struct GrokChatHistory: UsageLogParser {
    private var promptIndex: UInt64?
    private var votes: [UInt64: [String: [String: Int]]] = [:]

    mutating func parse(_ line: UnsafeRawBufferPointer) throws -> UsageLineOutcome? {
        do {
            guard JSONObjectReader(line) != nil else {
                return nil
            }
            let record = JSONValue(bytes: line)
            guard let kind = try record.member("type") else {
                return nil
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
                    return nil
                }
                votes[promptIndex, default: [:]][model, default: [:]][effort, default: 0] += 1
            default: break
            }
            return nil
        } catch {
            promptIndex = nil
            throw error
        }
    }

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
