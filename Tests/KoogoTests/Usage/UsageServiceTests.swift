import Foundation
import XCTest

@testable import Koogo

final class UsageServiceTests: UsageWorkspaceTestCase {
    func testDisabledProvidersAreNeitherScannedNorSummarized() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        try workspace.write(claudeLog(output: 40), to: workspace.claudeProjects.appending(path: "main.jsonl"))
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let all = await service.refresh(at: now)
        let codexOnly = await service.refresh(at: now, providers: [.codex])
        // Enabling a provider without logs changes no files but still adds its card.
        let codexAndGrok = await service.refresh(at: now, providers: [.codex, .grok])

        XCTAssertEqual(all.snapshot.summary.today.current.processedTokens, 170)
        XCTAssertEqual(Set(codexOnly.snapshot.providers.keys), [.codex])
        XCTAssertEqual(codexOnly.snapshot.summary.today.current.processedTokens, 120)
        XCTAssertEqual(codexOnly.ingestion.trackedFiles[.claude], 0)
        XCTAssertEqual(Set(codexAndGrok.snapshot.providers.keys), [.codex, .grok])
    }

    func testRefreshRebuildsSnapshotForNewDay() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20),
            to: workspace.codexSessions.appending(path: "session.jsonl")
        )
        let service = UsageService(locations: locations, calendar: usageTestCalendar)
        let current = await service.refresh(at: now).snapshot

        let nextDay = try XCTUnwrap(usageTestCalendar.date(byAdding: .day, value: 1, to: now))
        let refreshed = await service.refresh(at: nextDay).snapshot

        XCTAssertEqual(current.providers[.codex]?.today.processedTokens, 120)
        XCTAssertEqual(refreshed.providers[.codex]?.today, UsagePeriodSnapshot())
        XCTAssertEqual(refreshed.providers[.codex]?.week.processedTokens, 120)
    }

    func testUnpricedModelIsExcludedFromTotalsAndReported() async throws {
        let log = workspace.codexSessions.appending(path: "session.jsonl")
        try workspace.write(codexLog(input: 100, output: 20, model: "unknown-model"), to: log)
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let report = await service.refresh(at: now)

        XCTAssertEqual(report.snapshot.providers[.codex]?.month, UsagePeriodSnapshot())
        XCTAssertEqual(report.ingestion.trackedFiles, [.codex: 1, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.events, [.codex: 0, .claude: 0, .piAgent: 0, .grok: 0])
        XCTAssertEqual(report.ingestion.unpricedModels, ["unknown-model"])
    }

    func testColdScanRetainsComparisonPeriodsAndDiscardsOlderHistory() async throws {
        try workspace.write(
            codexLog(
                input: 100,
                output: 20,
                thread: "previous-day",
                usageTimestamp: "2026-08-24T17:00:00.000Z"
            ),
            to: workspace.codexSessions.appending(path: "previous-day.jsonl")
        )
        try workspace.write(
            codexLog(
                input: 200,
                output: 40,
                thread: "previous-month",
                usageTimestamp: "2026-07-25T17:00:00.000Z"
            ),
            to: workspace.codexSessions.appending(path: "previous-month.jsonl")
        )
        for index in 1...3 {
            try workspace.write(
                codexLog(
                    input: 1,
                    output: 0,
                    thread: "older-\(index)",
                    model: "gpt-5.6-luna",
                    usageTimestamp: "2026-06-30T17:00:00.000Z"
                ),
                to: workspace.codexSessions.appending(path: "older-\(index).jsonl")
            )
        }
        let service = UsageService(locations: locations, calendar: usageTestCalendar)

        let snapshot = await service.refresh(at: now).snapshot

        XCTAssertEqual(snapshot.summary.today.costChange, .decrease(fraction: 1))
        XCTAssertEqual(snapshot.summary.month.costChange, .decrease(fraction: Decimal(1) / 2))
        XCTAssertEqual(snapshot.providers[.codex]?.favorite?.modelName, "GPT 5.6 Sol")
    }
}
