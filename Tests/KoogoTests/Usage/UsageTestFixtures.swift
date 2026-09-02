import Foundation
import XCTest

@testable import Koogo

let usageTestTimestamp = Date(timeIntervalSince1970: 1_787_680_800)

struct UsageTestWorkspace {
    let root: URL
    let locations: UsageLocations
    let calendar: Calendar

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let codexSessions = root.appending(path: "codex/sessions", directoryHint: .isDirectory)
        let codexArchive = root.appending(path: "codex/archive", directoryHint: .isDirectory)
        let claudeProjects = root.appending(path: "claude/projects", directoryHint: .isDirectory)
        let piAgent = root.appending(path: "pi", directoryHint: .isDirectory)
        let piSessions = piAgent.appending(path: "sessions", directoryHint: .isDirectory)
        for directory in [codexSessions, codexArchive, claudeProjects, piSessions] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        locations = UsageLocations(
            logs: UsageLocations.Logs(
                codex: UsageLocations.Logs.Codex(
                    sessions: codexSessions,
                    archivedSessions: codexArchive
                ),
                claudeProjects: claudeProjects,
                piAgent: piSessions
            ),
            piModels: UsageLocations.PiModels(
                custom: piAgent.appending(path: "models.json"),
                store: piAgent.appending(path: "models-store.json")
            )
        )
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("UTC time zone must exist")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    func remove() throws {
        try FileManager.default.removeItem(at: root)
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

    func append(
        _ text: String,
        to url: URL,
        modificationDate: Date = usageTestTimestamp
    ) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path
        )
    }
}

/// Owns a fresh `UsageTestWorkspace` per test and evaluates it at `usageTestTimestamp`.
class UsageWorkspaceTestCase: XCTestCase {
    private(set) var workspace: UsageTestWorkspace!
    let now = usageTestTimestamp

    var locations: UsageLocations { workspace.locations }
    var calendar: Calendar { workspace.calendar }

    override func setUpWithError() throws {
        workspace = try UsageTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }
}

func usageEvent(
    _ provider: UsageProvider,
    id: Int = 0,
    model: UsageModelReference? = nil,
    effort: String? = nil,
    processedTokens: UInt64,
    costUSD: Decimal,
    at eventDate: Date = usageTestTimestamp
) -> UsageEvent {
    let usage = UsageRecord(
        timestamp: eventDate,
        processedTokens: processedTokens,
        costUSD: costUSD,
        modelTurn: model.map {
            UsageRecord.ModelTurn(model: $0, reasoningEffort: effort)
        }
    )
    switch provider {
    case .codex:
        return .codex(
            id: UsageEvent.CodexID(
                threadID: "thread-\(id)",
                turnID: nil,
                ordinal: nil,
                timestamp: eventDate,
                cumulativeTotal: processedTokens
            ),
            usage: usage
        )
    case .claude:
        return .claude(
            id: UsageEvent.ClaudeID(
                messageID: "message-\(id)",
                requestID: "request-\(id)"
            ),
            usage: usage,
            revision: UsageEvent.ClaudeRevision(
                outputTokens: processedTokens,
                metadataCompleteness: 0,
                processedTokens: processedTokens,
                timestamp: eventDate
            )
        )
    case .piAgent:
        return .piAgent(entryID: "entry-\(id)", usage: usage)
    }
}

func codexTokenUsage(
    uncachedInput: UInt64,
    cachedInput: UInt64 = 0,
    cacheWriteInput: UInt64 = 0,
    output: UInt64 = 0
) -> CodexTokenUsage {
    guard
        let usage = CodexTokenUsage(
            input: uncachedInput + cachedInput + cacheWriteInput,
            cachedInput: cachedInput,
            cacheWrite: cacheWriteInput,
            output: output,
            reasoningOutput: 0,
            processed: uncachedInput + cachedInput + cacheWriteInput + output
        )
    else {
        preconditionFailure("invalid codex usage fixture")
    }
    return usage
}

func claudeBillableUsage(
    uncachedInput: UInt64 = 0,
    cachedInput: UInt64 = 0,
    cacheWrite5MinuteInput: UInt64 = 0,
    cacheWrite1HourInput: UInt64 = 0,
    output: UInt64 = 0,
    speed: ClaudeUsageSpeed = .standard,
    inferenceGeo: String? = nil,
    webSearchRequests: UInt64 = 0
) -> ClaudeBillableUsage {
    guard
        let tokens = ClaudeTokenUsage(
            input: uncachedInput,
            cacheRead: cachedInput,
            cacheCreation: .byDuration(
                fiveMinute: cacheWrite5MinuteInput,
                oneHour: cacheWrite1HourInput
            ),
            output: output
        )
    else {
        preconditionFailure("invalid claude usage fixture")
    }
    return ClaudeBillableUsage(
        tokens: tokens,
        speed: speed,
        inferenceGeo: inferenceGeo,
        webSearchRequests: webSearchRequests
    )
}

func codexLog(
    input: Int,
    output: Int,
    thread: String = "thread",
    model: String = "gpt-5.6-sol",
    usageTimestamp: String = "2026-08-25T12:00:00.000Z"
) -> String {
    [
        codexSessionMetadata(thread: thread),
        codexTurnContext(model: model),
        codexToken(
            timestamp: usageTimestamp,
            lastInput: input,
            lastOutput: output,
            totalInput: input,
            totalOutput: output
        ),
        "",
    ].joined(separator: "\n")
}

func codexSessionMetadata(thread: String) -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"\(thread)"}}
    """
}

func codexTurnContext(model: String) -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"turn","model":"\(model)","effort":"high"}}
    """
}

func codexToken(
    timestamp: String,
    lastInput: Int,
    lastOutput: Int,
    totalInput: Int,
    totalOutput: Int
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":0,"output_tokens":\(lastOutput),"reasoning_output_tokens":0,"total_tokens":\(lastInput + lastOutput)},"total_token_usage":{"input_tokens":\(totalInput),"cached_input_tokens":0,"output_tokens":\(totalOutput),"reasoning_output_tokens":0,"total_tokens":\(totalInput + totalOutput)},"model_context_window":1000}}}
    """
}

func claudeLog(output: Int, requestID: String? = "request") -> String {
    let request = requestID.map { "\"requestId\":\"\($0)\"," } ?? ""
    return """
        {"type":"assistant","timestamp":"2026-08-25T12:30:00.000Z",\(request)"message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":\(output)}}}

        """
}

func parse(_ line: String, with parser: inout some UsageLogParser) -> UsageEvent? {
    Data(line.utf8).withUnsafeBytes {
        guard case .event(let event)? = parser.parse($0, decoder: JSONDecoder()) else {
            return nil
        }
        return event
    }
}
