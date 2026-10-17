import Foundation
import XCTest

@testable import Koogo

final class UsageLogDiscoveryTests: UsageWorkspaceTestCase {
    func testColdScanIgnoresJSONLSymlinks() async throws {
        let target = workspace.root.appending(path: "target.log")
        try workspace.write(codexLog(input: 100, output: 20), to: target)
        try FileManager.default.createSymbolicLink(
            at: workspace.codexSessions.appending(path: "session.jsonl"),
            withDestinationURL: target
        )
        let service = makePipeline()

        let snapshot = await service.run(at: usageTestTimestamp, providers: Provider.allCases).snapshot

        XCTAssertEqual(snapshot.providers[.codex]?.periods[.last30Days].total, UsagePeriodSnapshot())
    }

    func testSymlinkedLogRootIsWalked() async throws {
        let target = workspace.root.appending(path: "sessions-target", directoryHint: .isDirectory)
        try workspace.write(codexLog(input: 100, output: 20), to: target.appending(path: "session.jsonl"))
        try FileManager.default.removeItem(at: workspace.codexSessions)
        try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: target)
        let service = makePipeline()

        let report = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(report.snapshot.todayTokens(.codex), 120)
        let root = report.ingestion.logRoots.first { $0.path == workspace.codexSessions.path }
        XCTAssertEqual(root?.exists, true)

        try workspace.append(
            codexTokenCount(
                last: codexUsage(input: 50, output: 10),
                total: codexUsage(input: 150, output: 30)
            ) + "\n",
            to: target.appending(path: "session.jsonl")
        )
        let appended = try await refresh(service) { $0.snapshot.todayTokens(.codex) != 120 }
        XCTAssertEqual(appended.snapshot.todayTokens(.codex), 180)
    }

    func testRetargetedLogRootSymlinkIsWalked() async throws {
        let first = workspace.root.appending(path: "first-target", directoryHint: .isDirectory)
        let second = workspace.root.appending(path: "second-target", directoryHint: .isDirectory)
        try workspace.write(codexLog(input: 100, output: 20), to: first.appending(path: "session.jsonl"))
        try workspace.write(codexLog(input: 40, output: 10), to: second.appending(path: "session.jsonl"))
        try FileManager.default.removeItem(at: workspace.codexSessions)
        try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: first)
        let service = makePipeline()
        let initial = await service.run(at: usageTestTimestamp, providers: Provider.allCases)
        XCTAssertEqual(initial.snapshot.todayTokens(.codex), 120)

        try FileManager.default.removeItem(at: workspace.codexSessions)
        try FileManager.default.createSymbolicLink(at: workspace.codexSessions, withDestinationURL: second)
        let retargeted = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(retargeted.snapshot.todayTokens(.codex), 50)
    }

    func testDirectoriesThatAppearMoveInOrVanishLaterAreFollowed() async throws {
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        try workspace.write(
            claudeLog(output: 40),
            to: workspace.claudeProjects.appending(path: "project/session/subagents/agent.jsonl")
        )
        let created = try await refresh(service) { $0.ingestion.trackedFiles[.claude] != 0 }
        XCTAssertEqual(created.snapshot.todayTokens(.claude), 50)

        let staging = workspace.root.appending(path: "staging", directoryHint: .isDirectory)
        try workspace.write(codexLog(input: 100, output: 20), to: staging.appending(path: "2026/08/25/rollout.jsonl"))
        try FileManager.default.moveItem(
            at: staging.appending(path: "2026"),
            to: workspace.codexSessions.appending(path: "2026")
        )
        let movedIn = try await refresh(service) { $0.ingestion.trackedFiles[.codex] != 0 }
        XCTAssertEqual(movedIn.snapshot.todayTokens(.codex), 120)

        try FileManager.default.removeItem(at: workspace.claudeProjects.appending(path: "project"))
        let removed = try await refresh(service) { $0.ingestion.trackedFiles[.claude] == 0 }
        XCTAssertEqual(removed.snapshot.todayTokens(.claude), 0)
    }

    func testHiddenDirectoriesStayUnscannedWhenTheyChangeLater() async throws {
        let hidden = workspace.codexSessions.appending(path: ".cache/deep", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        let service = makePipeline()
        _ = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        try workspace.write(codexLog(input: 100, output: 20, turn: "cached"), to: hidden.appending(path: "a.jsonl"))
        try workspace.write(
            codexLog(input: 1, output: 0, turn: "witness"),
            to: workspace.codexArchivedSessions.appending(path: "witness.jsonl")
        )
        let report = try await refresh(service) { $0.ingestion.trackedFiles[.codex] != 0 }

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 1)
        XCTAssertEqual(report.snapshot.todayTokens(.codex), 1)
    }

    func testAppearingLogRootRefreshesTheReport() async throws {
        let archived = workspace.codexArchivedSessions
        try FileManager.default.removeItem(at: archived)
        let service = makePipeline()
        let missing = await service.run(at: usageTestTimestamp, providers: Provider.allCases)
        XCTAssertEqual(missing.ingestion.logRoots.first { $0.path == archived.path }?.exists, false)

        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let appeared = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(appeared.ingestion.logRoots.first { $0.path == archived.path }?.exists, true)
    }

    func testHiddenFilesAndDirectoriesAreNotScanned() async throws {
        try workspace.write(
            codexLog(input: 100, output: 20, turn: "cached"),
            to: workspace.codexSessions.appending(path: ".cache/a.jsonl")
        )
        try workspace.write(
            codexLog(input: 100, output: 20, turn: "hidden"),
            to: workspace.codexSessions.appending(path: ".b.jsonl")
        )
        let flagged = workspace.codexSessions.appending(path: "flagged.jsonl")
        try workspace.write(codexLog(input: 100, output: 20, turn: "flagged"), to: flagged)
        XCTAssertEqual(chflags(flagged.path, UInt32(UF_HIDDEN)), 0)
        let service = makePipeline()

        let report = await service.run(at: usageTestTimestamp, providers: Provider.allCases)

        XCTAssertEqual(report.ingestion.trackedFiles[.codex], 0)
    }
}
