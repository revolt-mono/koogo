import Foundation
import XCTest

@testable import Koogo

final class UsageServiceTests: XCTestCase {
    private var root: URL!
    private var locations: UsageLogLocations!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let codexSessions = root.appending(path: "codex/sessions", directoryHint: .isDirectory)
        let codexArchive = root.appending(path: "codex/archive", directoryHint: .isDirectory)
        let claudeProjects = root.appending(path: "claude/projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexSessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexArchive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeProjects, withIntermediateDirectories: true)
        locations = UsageLogLocations(
            codexSessions: codexSessions,
            codexArchivedSessions: codexArchive,
            claudeProjects: claudeProjects
        )
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        now = try XCTUnwrap(parseUsageTimestamp("2026-08-25T18:00:00.000Z"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testColdScanDeduplicatesClaudePartialsAndProviderSnapshots() async throws {
        let codex = locations.codexSessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: codex)

        let claudeMain = locations.claudeProjects.appending(path: "project/main.jsonl")
        let claudeCopy = locations.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2), to: claudeMain)
        try write(claudeLog(output: 40), to: claudeCopy)

        let service = UsageService(locations: locations, calendar: calendar)
        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
        XCTAssertEqual(
            snapshot.codex.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "GPT 5.6 Sol",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(snapshot.claude.today.processedTokens, 50)
        XCTAssertEqual(
            snapshot.claude.favorite,
            ProviderUsageSnapshot.Favorite(
                modelName: "Claude Opus 5",
                reasoningEffort: nil
            )
        )
    }

    func testRefreshReadsOnlyCompleteAppendedLines() async throws {
        let log = locations.codexSessions.appending(path: "session.jsonl")
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
        XCTAssertEqual(beforeNewline.codex.today.processedTokens, 120)

        try append("\n", to: log)
        let afterNewline = await service.refresh(at: now)
        XCTAssertEqual(afterNewline.codex.today.processedTokens, 180)
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
            to: locations.codexSessions.appending(path: "session.jsonl")
        )
        let model = UsageModel(
            usageService: UsageService(locations: locations, calendar: calendar)
        )
        let deadline = ContinuousClock.now + .seconds(1)

        while model.snapshot == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            try XCTUnwrap(model.snapshot).codex.month.processedTokens,
            120
        )
    }

    func testArchiveCopyDoesNotDoubleCountAndReplacementDropsRemovedEvents() async throws {
        let active = locations.codexSessions.appending(path: "session.jsonl")
        let contents = codexLog(input: 100, output: 20)
        try write(contents, to: active)
        let service = UsageService(locations: locations, calendar: calendar)
        _ = await service.refresh(at: now)

        let archived = locations.codexArchivedSessions.appending(path: "session.jsonl")
        try write(contents, to: archived)
        let copied = await service.refresh(at: now)
        XCTAssertEqual(copied.codex.today.processedTokens, 120)

        try write(codexLog(input: 40, output: 10, thread: "replacement"), to: active)
        try FileManager.default.removeItem(at: archived)
        let replaced = await service.refresh(at: now)
        XCTAssertEqual(replaced.codex.today.processedTokens, 50)
    }

    func testUnknownModelIsIgnoredCompletely() async throws {
        let log = locations.codexSessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.month, .zero)
    }

    func testCodexIdenticalRequestUsageAtTheSameTimestampCountsTwice() async throws {
        let log = locations.codexSessions.appending(path: "session.jsonl")
        let timestamp = "2026-08-25T12:00:00.000Z"
        let contents = [
            "{\"timestamp\":\"2026-08-25T11:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"thread\"}}",
            "{\"timestamp\":\"2026-08-25T11:30:00.000Z\",\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"turn\",\"model\":\"gpt-5.6-sol\",\"effort\":\"high\"}}",
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

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testColdScanUsesEventTimestampsInsteadOfFileModificationDate() async throws {
        let log = locations.codexSessions.appending(path: "session.jsonl")
        try write(codexLog(input: 100, output: 20), to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: log.path
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testColdScanRetainsPreviousComparisonPeriods() async throws {
        try write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-day",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: locations.codexSessions.appending(path: "previous-day.jsonl")
        )
        try write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-month",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: locations.codexSessions.appending(path: "previous-month.jsonl")
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.summary.today.cost.previousUSD, Decimal(string: "0.0011"))
        XCTAssertEqual(snapshot.summary.month.cost.previousUSD, Decimal(string: "0.0022"))
    }

    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = root.appending(path: "target.log")
        try write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: locations.codexSessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.month, .zero)
    }

    func testColdScanParsesLinesAcrossReadChunks() async throws {
        let log = locations.codexSessions.appending(path: "session.jsonl")
        let ignored = "{\"type\":\"ignored\",\"padding\":\""
            + String(repeating: "x", count: 4_194_304)
            + "\"}\n"
        try write(ignored + codexLog(input: 100, output: 20), to: log)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.codex.today.processedTokens, 120)
    }

    func testClaudePartialsAndCopiesWithoutStableIDsAreIgnored() async throws {
        let partial = locations.claudeProjects.appending(path: "project/main.jsonl")
        let copy = locations.claudeProjects.appending(path: "project/agent/copy.jsonl")
        try write(claudeLog(output: 2, requestID: nil), to: partial)
        try write(claudeLog(output: 40, requestID: nil), to: copy)
        let service = UsageService(locations: locations, calendar: calendar)

        let snapshot = await service.refresh(at: now)

        XCTAssertEqual(snapshot.claude.month, .zero)
    }

    func testCalendarPeriodsUseLocalCalendarAndConfiguredFirstWeekday() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        local.firstWeekday = 2
        let date = try XCTUnwrap(parseUsageTimestamp("2026-03-11T12:00:00.000Z"))
        let intervals = UsagePeriodIntervals.containing(date, calendar: local)

        XCTAssertEqual(
            local.dateComponents(
                [.year, .month, .day],
                from: intervals.day.current.lowerBound
            ),
            DateComponents(year: 2026, month: 3, day: 11)
        )
        XCTAssertEqual(
            local.dateComponents([.year, .month, .day], from: intervals.week.lowerBound),
            DateComponents(year: 2026, month: 3, day: 9)
        )
        XCTAssertEqual(
            local.dateComponents(
                [.year, .month, .day],
                from: intervals.month.current.lowerBound
            ),
            DateComponents(year: 2026, month: 3, day: 1)
        )
        XCTAssertEqual(
            local.dateComponents(
                [.year, .month, .day, .hour],
                from: intervals.day.previous.through
            ),
            DateComponents(year: 2026, month: 3, day: 10, hour: 5)
        )
        XCTAssertEqual(
            local.dateComponents(
                [.year, .month, .day, .hour],
                from: intervals.month.previous.through
            ),
            DateComponents(year: 2026, month: 2, day: 11, hour: 5)
        )
    }

    func testPreviousDayComparisonPreservesWallClockTimeAcrossDST() throws {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let date = try XCTUnwrap(parseUsageTimestamp("2026-03-08T10:30:00Z"))

        let previousEnd = UsagePeriodIntervals.containing(date, calendar: local).day.previous.through

        XCTAssertEqual(
            local.dateComponents([.year, .month, .day, .hour, .minute], from: previousEnd),
            DateComponents(year: 2026, month: 3, day: 7, hour: 3, minute: 30)
        )
    }

    private func codexLog(
        input: Int,
        output: Int,
        thread: String = "thread",
        model: String = "gpt-5.6-sol",
        usageTimestamp: String = "2026-08-25T12:00:00.000Z"
    ) -> String {
        [
            "{\"timestamp\":\"2026-08-25T11:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(thread)\"}}",
            "{\"timestamp\":\"2026-08-25T11:30:00.000Z\",\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"turn\",\"model\":\"\(model)\",\"effort\":\"high\"}}",
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
