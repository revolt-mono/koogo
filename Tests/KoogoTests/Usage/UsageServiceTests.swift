import Foundation
import XCTest

@testable import Koogo

final class UsageServiceTests: XCTestCase {
    private var root: URL!
    private var locations: UsageLocations!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let codexSessions = root.appending(path: "codex/sessions", directoryHint: .isDirectory)
        let codexArchive = root.appending(path: "codex/archive", directoryHint: .isDirectory)
        let claudeProjects = root.appending(path: "claude/projects", directoryHint: .isDirectory)
        let piAgent = root.appending(path: "pi", directoryHint: .isDirectory)
        let piSessions = piAgent.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexArchive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeProjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: piSessions, withIntermediateDirectories: true)
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
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        now = usageTestTimestamp
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testColdScanDeduplicatesClaudePartialsAndProviderSnapshots() async throws {
        let codex = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: codex)

        let claudeMain = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let claudeCopy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2), to: claudeMain)
        try write(claudeLog(output: 40), to: claudeCopy)

        let service = UsageService(locations: locations, calendar: calendar)
        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 120)
        XCTAssertEqual(
            snapshot.codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Sol",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(snapshot.claude.last24Hours.processedTokens, 50)
        XCTAssertEqual(
            snapshot.claude.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "Opus 5",
                reasoningEffort: nil
            )
        )
    }

    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now)

        let appended = codexToken(
            timestamp: "2026-08-25T13:00:00.000Z",
            lastInput: 50,
            lastOutput: 10,
            totalInput: 150,
            totalOutput: 30
        )
        try append(appended, to: log)
        let beforeNewline = await service.refresh(at: now)
        XCTAssertEqual(beforeNewline.codex.last24Hours.processedTokens, 120)

        try append("\n", to: log)
        let afterNewline = await service.refresh(at: now)
        XCTAssertEqual(afterNewline.codex.last24Hours.processedTokens, 180)
    }

    func testRefreshAdvancesRollingWindow() async throws {
        try write(
            codexLog(input: 100, output: 20),
            to: locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let service = UsageService(locations: locations, calendar: calendar)
        let current = await service.refresh(at: now)

        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let refreshed = await service.refresh(at: nextDay)

        XCTAssertEqual(current.codex.last24Hours.processedTokens, 120)
        XCTAssertEqual(refreshed.codex.last24Hours, .zero)
        XCTAssertEqual(refreshed.codex.last7Days.processedTokens, 120)
    }

    @MainActor
    func testUsageModelStartsColdScanOnInitialization() async throws {
        try write(
            codexLog(
                input: 100,
                output: 20,
                usageTimestamp: ISO8601DateFormatter().string(
                    from: calendar.startOfDay(for: Date())
                )
            ),
            to: locations.logs.codex.sessions.appending(path: "session.jsonl")
        )
        let model = UsageModel(
            usageService: UsageService(locations: locations, calendar: calendar)
        )
        let deadline = ContinuousClock.now + .seconds(1)

        while model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            try XCTUnwrap(model.snapshot).codex.last30Days.processedTokens,
            120
        )
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try write(contents, to: active)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now)

        let archived = locations.logs.codex.archivedSessions.appending(path: "session.jsonl")
        try write(contents, to: archived)
        let copied = await service.refresh(at: now)
        XCTAssertEqual(copied.codex.last24Hours.processedTokens, 120)

        try write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.refresh(at: now)
        XCTAssertEqual(replaced.codex.last24Hours.processedTokens, 50)
    }

    func testUnknownModelIsIgnoredCompletely() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last30Days, .zero)
    }

    func testCodexIdenticalRequestUsageAtTheSameTimestampCountsTwice() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let timestamp = "2026-08-25T12:00:00.000Z"
        let contents = [
            codexSessionMetadata(thread: "thread"),
            codexTurnContext(model: "gpt-5.6-sol"),
            codexToken(
                timestamp: timestamp,
                lastInput: 50,
                lastOutput: 10,
                totalInput: 50,
                totalOutput: 10
            ),
            codexToken(
                timestamp: timestamp,
                lastInput: 50,
                lastOutput: 10,
                totalInput: 100,
                totalOutput: 20
            ),
            "",
        ].joined(separator: "\n")
        try write(contents, to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 120)
    }

    func testColdScanUsesEventTimestampsInsteadOfFileModificationDate() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 120)
    }

    func testColdScanRetainsPreviousComparisonPeriods() async throws {
        try write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-24-hours",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-24-hours.jsonl")
        )
        try write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-30-days",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: locations.logs.codex.sessions.appending(path: "previous-30-days.jsonl")
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.summary.last24Hours.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.last30Days.costChange, .decrease(fraction: Decimal(1) / 2))
    }

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = root.appending(path: "target.log")
        try write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: locations.logs.codex.sessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last30Days, .zero)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = locations.logs.codex.sessions.appending(path: "session.jsonl")
        let ignored =
            "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.last24Hours.processedTokens, 120)
    }

    func testClaudePartialsAndCopiesWithoutStableIDsAreIgnored() async throws {
        let partial = locations.logs.claudeProjects.appending(path: "project/main.jsonl")
        let copy = locations.logs.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2, requestID: nil), to: partial)
        try write(claudeLog(output: 40, requestID: nil), to: copy)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.claude.last30Days, .zero)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now as Date], ofItemAtPath: url.path)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try FileManager.default.setAttributes([.modificationDate: now as Date], ofItemAtPath: url.path)
    }
}

private func codexLog(
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

private func codexSessionMetadata(thread: String) -> String {
    """
    {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"\(thread)"}}
    """
}

private func codexTurnContext(model: String) -> String {
    """
    {"timestamp":"2026-08-25T11:30:00.000Z","type":"turn_context","payload":{"turn_id":"turn","model":"\(model)","effort":"high"}}
    """
}

private func codexToken(
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

private func claudeLog(output: Int, requestID: String? = "request") -> String {
    let request = requestID.map { "\"requestId\":\"\($0)\"," } ?? ""
    return """
        {"type":"assistant","timestamp":"2026-08-25T12:30:00.000Z",\(request)"message":{"id":"message","model":"claude-opus-5","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":\(output)}}}

        """
}
