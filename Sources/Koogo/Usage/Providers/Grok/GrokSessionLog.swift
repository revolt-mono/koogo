import Foundation

/// One Grok session directory: `updates.jsonl` bills each prompt, and `chat_history.jsonl` records the reasoning effort the surviving branch ran with.
struct GrokSessionLog: TrackedLog {
    private var updates: AppendOnlyFile
    private var turns: ParsedLines<GrokUsageLogParser>
    private var history: AppendOnlyFile?
    private let historyURL: URL
    private var efforts = GrokChatHistory()
    /// The billed turns, each carrying the effort its surviving prompt ran with.
    private(set) var events = UsageEventIndex()

    var tally: LogTally {
        var tally = turns.tally
        tally.countMalformedLines(efforts.malformedLines)
        return tally
    }

    /// Admits `updates.jsonl` once its session has a readable summary. A subagent session is skipped, since the parent turn that spawned it already includes its usage.
    init?(_ url: URL, since windowStart: Date) {
        let sessionURL = url.deletingLastPathComponent()
        guard let data = try? Data(contentsOf: sessionURL.appending(path: "summary.json")),
            let summary = try? JSONDecoder().decode(GrokSessionSummary.self, from: data),
            summary.kind?.hasPrefix("subagent") != true,
            let updates = AppendOnlyFile(url)
        else {
            return nil
        }
        self.updates = updates
        turns = ParsedLines(since: windowStart)
        historyURL = sessionURL.appending(path: "chat_history.jsonl")
        guard self.updates.read(into: &turns) != .unreadable else {
            return nil
        }
        _ = readHistory()
        joinEfforts()
    }

    mutating func sync(observed metadata: UsageFileMetadata) -> Bool {
        let updatesChanged = updates.observe(metadata) && updates.read(into: &turns) != .nothingNew
        let historyChanged = readHistory()
        guard updatesChanged || historyChanged else {
            return false
        }
        joinEfforts()
        return true
    }

    mutating func discard(before windowStart: Date) {
        turns.discard(before: windowStart)
        joinEfforts()
    }

    private mutating func readHistory() -> Bool {
        guard let metadata = UsageFileMetadata(path: historyURL.path) else {
            let removed = history != nil
            history = nil
            efforts = GrokChatHistory()
            return removed
        }
        if history == nil {
            history = AppendOnlyFile(historyURL)
            efforts = GrokChatHistory()
        } else if history?.observe(metadata) != true {
            return false
        }
        guard let read = history?.read(into: &efforts) else {
            return false
        }
        return read != .nothingNew
    }

    /// Attaches each surviving prompt's voted effort to its billed turn; a turn the history no longer names keeps none.
    private mutating func joinEfforts() {
        let promptIndices = Dictionary(turns.parser.promptTurns.map { ($0.value, $0.key) }) { first, _ in first }
        events = UsageEventIndex(
            distinct: turns.events.values.map { event in
                guard let promptIndex = promptIndices[event.id], let turn = event.record.modelTurn,
                    let effort = efforts.effort(promptIndex: promptIndex, model: turn.model.rawValue)
                else {
                    return event
                }
                return UsageEvent(
                    id: event.id,
                    record: UsageRecord(
                        timestamp: event.record.timestamp,
                        processedTokens: event.record.processedTokens,
                        costUSD: event.record.costUSD,
                        modelTurn: .init(model: turn.model, reasoningEffort: effort)
                    ),
                    revision: UsageEvent.Revision(outputTokens: 0, metadataCompleteness: 1)
                )
            }
        )
    }
}

/// Reasoning effort votes per prompt and model from `chat_history.jsonl`.
struct GrokChatHistory: LineConsumer, Sendable {
    private var promptIndex: UInt64?
    private var votes: [UInt64: [String: [String: Int]]] = [:]
    private(set) var malformedLines = 0

    mutating func restart() {
        self = GrokChatHistory()
    }

    mutating func consume(_ line: UnsafeRawBufferPointer) {
        do {
            try record(line)
        } catch {
            promptIndex = nil
            malformedLines += 1
        }
    }

    func effort(promptIndex: UInt64, model: String) -> String? {
        votes[promptIndex]?[model]?.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
    }

    private mutating func record(_ line: UnsafeRawBufferPointer) throws {
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
    }
}

private struct GrokSessionSummary: Decodable {
    let kind: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "session_kind"
    }
}
