import Foundation
import XCTest

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)

let usageTestCalendar: Calendar = {
    guard let utc = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("UTC time zone must exist")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    calendar.firstWeekday = 2
    return calendar
}()

struct UsageTestWorkspace {
    let root: URL

    var codexSessions: URL { logDirectory(.codex, "sessions") }
    var codexArchivedSessions: URL { logDirectory(.codex, "archived_sessions") }
    var claudeProjects: URL { logDirectory(.claude, "projects") }
    var piSessions: URL { logDirectory(.piAgent, "sessions") }
    var grokSessions: URL { logDirectory(.grok, "sessions") }

    init(root: URL) throws {
        self.root = root
        for provider in Provider.allCases {
            for directory in provider.usageLogDirectories {
                try FileManager.default.createDirectory(
                    at: logDirectory(provider, directory),
                    withIntermediateDirectories: true
                )
            }
        }
    }

    func home(of provider: Provider) -> URL {
        provider.home(under: root)
    }

    private func logDirectory(_ provider: Provider, _ directory: String) -> URL {
        home(of: provider).appending(path: directory, directoryHint: .isDirectory)
    }

    func write(
        _ text: String,
        to url: URL,
        modificationDate: Date = usageTestTimestamp
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path
        )
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: usageTestTimestamp], ofItemAtPath: url.path)
    }
}

class UsageWorkspaceTestCase: XCTestCase {
    private(set) var workspace: UsageTestWorkspace!
    let now = usageTestTimestamp

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace(root: try makeTemporaryDirectory())
    }

    func makePipeline() -> UsagePipeline {
        UsagePipeline(home: workspace.root, calendar: usageTestCalendar)
    }
}

func usageEvent(
    _ provider: Provider,
    id: Int = 0,
    model: String? = nil,
    effort: String? = nil,
    processedTokens: UInt64,
    costUSD: Decimal,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let record = UsageRecord(
        timestamp: eventDate,
        processedTokens: processedTokens,
        costUSD: costUSD,
        modelTurn: model.map { UsageRecord.ModelTurn(model: ModelID($0), reasoningEffort: effort) }
    )
    let eventID: UsageEventID =
        switch provider {
        case .codex: .codex(turnID: "turn-\(id)", cumulativeTotal: processedTokens)
        case .claude: .claude(messageID: "message-\(id)", requestID: "request-\(id)")
        case .piAgent: .piAgent(entryID: "entry-\(id)")
        case .grok: .grok(eventID: "event-\(id)", timestampMilliseconds: grokMilliseconds(eventDate))
        }
    return UsageEvent(id: eventID, record: record)
}

func grokMilliseconds(_ date: Date) -> UInt64 {
    UInt64(date.timeIntervalSince1970 * 1_000)
}

func usageSnapshot(
    events: [UsageEvent],
    providers: Set<Provider> = Set(Provider.allCases),
    intervals: UsagePeriodIntervals
) -> UsageSnapshot {
    var builder = UsageSnapshotBuilder(providers: providers, intervals: intervals)
    for event in events {
        builder.add(event)
    }
    return builder.snapshot(modelName: ModelNames().name)
}

func codexLog(
    input: Int,
    output: Int,
    thread: String = "thread",
    model: String = "gpt-5.6-sol",
    usageTimestamp: String = "2026-08-25T12:00:00.000Z"
) -> String {
    let usage = codexUsage(input: input, output: output)
    return [
        codexMeta(thread: thread),
        codexTurn(model: model),
        codexTokenCount(last: usage, total: usage, at: usageTimestamp),
        "",
    ].joined(separator: "\n")
}

func codexMeta(thread: String = "thread") -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"\(thread)"}}
    """
}

func codexTurn(id: String = "turn", model: String = "gpt-5.6-sol", effort: String = "high") -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"\(id)","model":"\(model)","effort":"\(effort)"}}
    """
}

func codexUsage(
    input: Int,
    output: Int,
    cached: Int = 0,
    cacheWrite: Int? = nil,
    total: Int? = nil
) -> String {
    let cacheWriteField = cacheWrite.map { "\"cache_write_input_tokens\":\($0)," } ?? ""
    return """
        {"input_tokens":\(input),"cached_input_tokens":\(cached),\(cacheWriteField)"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(total ?? input + output)}
        """
}

func codexTokenCount(last: String, total: String, at timestamp: String = "2026-08-25T12:00:00.000Z") -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":\(last),"total_token_usage":\(total),"model_context_window":1000}}}
    """
}

func claudeAssistant(model: String, usage: String, effort: String? = nil) -> String {
    let effortField = effort.map { "\"effort\":\"\($0)\"," } ?? ""
    return """
        {"type":"assistant","timestamp":"2026-08-25T12:00:00.000Z","requestId":"request",\(effortField)"message":{"id":"message","model":"\(model)","usage":{\(usage)}}}
        """
}

func claudeLog(output: Int) -> String {
    claudeAssistant(model: "claude-opus-5", usage: #""input_tokens":10,"output_tokens":\#(output)"#) + "\n"
}

func piAssistant(id: String, parentID: String?, model: String, usage: String) -> String {
    let parent = parentID.map { "\"\($0)\"" } ?? "null"
    return """
        {"type":"message","id":"\(id)","parentId":\(parent),"timestamp":"2026-08-25T12:00:00.000Z","message":{"role":"assistant","provider":"provider","model":"\(model)","timestamp":1787680800000,"usage":\(usage)}}
        """
}

func piUsage(
    input: Int,
    output: Int = 0,
    cacheRead: Int = 0,
    cacheWrite: Int = 0,
    cost: String
) -> String {
    """
    {"input":\(input),"output":\(output),"cacheRead":\(cacheRead),"cacheWrite":\(cacheWrite),"totalTokens":\(input + output + cacheRead + cacheWrite),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\(cost)}}
    """
}

struct GrokModelRow {
    var input = 1_000_000
    var cachedInput = 400_000
    var output = 100_000
    var calls = 10
}

func grokTurn(
    eventID: String,
    at date: Date = usageTestTimestamp,
    models: [String: GrokModelRow] = ["grok-4.6-build": GrokModelRow()]
) -> String {
    let milliseconds = Int(date.timeIntervalSince1970 * 1_000)
    let totalTokens = models.values.map { $0.input + $0.output }.reduce(0, +)
    let modelUsage = models.map { model, row in
        """
        "\(model)":{"inputTokens":\(row.input),"cachedReadTokens":\(row.cachedInput),"outputTokens":\(row.output),\
        "modelCalls":\(row.calls),"costUsdTicks":1}
        """
    }
    return """
        {"timestamp":1,"method":"_x.ai/session/update","params":{"sessionId":"session","update":{\
        "sessionUpdate":"turn_completed","prompt_id":"prompt","stop_reason":"end_turn","usage":{\
        "totalTokens":\(totalTokens),"costUsdTicks":1,"modelUsage":{\(modelUsage.joined(separator: ","))}}},\
        "_meta":{"eventId":"\(eventID)","agentTimestampMs":\(milliseconds)}}}
        """
}

func parse(_ line: String, with parser: inout some UsageLogParser) throws -> UsageLineOutcome? {
    try Data(line.utf8).withUnsafeBytes { try parser.parse($0) }
}

extension UsageLineOutcome {
    var event: UsageEvent? {
        guard case .event(let event) = self else {
            return nil
        }
        return event
    }

    var unpricedModelID: String? {
        guard case .unpricedModel(let id, _) = self else {
            return nil
        }
        return id
    }
}
