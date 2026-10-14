import Foundation
import XCTest

@testable import Koogo

final class OrphanedAgentProcessesTests: XCTestCase {
    private let identity = ProcessIdentity(pid: 42, startTicks: 0)

    func testOrphanedAgentProcessRecognizesAgentExecutablesReparentedToLaunchd() {
        let orphans = [
            "/Users/me/.local/share/claude/versions/2.1.284",
            "/Users/me/.codex/packages/standalone/releases/0.158.0-aarch64-apple-darwin/bin/codex",
            "/Users/me/.grok/downloads/grok-1.0.45-macos-aarch64",
        ].map { OrphanedAgentProcess(identity, parentPID: 1, executablePath: $0)?.provider }

        XCTAssertEqual(orphans, [.claude, .codex, .grok])
        XCTAssertNil(
            OrphanedAgentProcess(
                identity,
                parentPID: 900,
                executablePath: "/Users/me/.local/share/claude/versions/2.1.284"
            )
        )
        XCTAssertNil(OrphanedAgentProcess(identity, parentPID: 1, executablePath: "/opt/tool/versions/2.1.284"))
        XCTAssertNil(OrphanedAgentProcess(identity, parentPID: 1, executablePath: "/Users/me/.local/share/claude/node"))
    }

    func testOrphanedAgentProcessesIsNilWhenEmpty() {
        XCTAssertNil(OrphanedAgentProcesses([]))
    }

    func testOrphanedAgentProcessesSummarizesCountsPerProviderInOrder() throws {
        let processes = OrphanedAgentProcesses([
            try orphan(pid: 7, executablePath: "/Users/me/.codex/bin/codex"),
            try orphan(pid: 5, executablePath: "/Users/me/.local/share/claude/versions/2.1.284"),
            try orphan(pid: 3, executablePath: "/Users/me/.codex/bin/codex"),
        ])

        XCTAssertEqual(processes?.summary, "2 codex, 1 claude")
    }

    private func orphan(pid: pid_t, executablePath: String) throws -> OrphanedAgentProcess {
        try XCTUnwrap(
            OrphanedAgentProcess(ProcessIdentity(pid: pid, startTicks: 0), parentPID: 1, executablePath: executablePath)
        )
    }
}
