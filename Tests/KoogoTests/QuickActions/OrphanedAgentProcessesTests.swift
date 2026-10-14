import Foundation
import XCTest

@testable import Koogo

final class OrphanedAgentProcessesTests: XCTestCase {
    private let identity = ProcessIdentity(pid: 42, startTicks: 0)
    private let claudePath = "/Users/me/.local/share/claude/versions/2.1.284"

    func testOrphanedAgentProcessRecognizesAgentExecutablesWithoutATerminal() {
        let orphans = [
            claudePath,
            "/Users/me/.codex/packages/standalone/releases/0.158.0-aarch64-apple-darwin/bin/codex",
            "/Users/me/.grok/downloads/grok-1.0.45-macos-aarch64",
        ].map { orphan(parentPID: 1, executablePath: $0)?.provider }

        XCTAssertEqual(orphans, [.claude, .codex, .grok])
        XCTAssertNotNil(orphan(parentPID: 900, executablePath: claudePath), "daemon children count without launchd")
        XCTAssertNil(orphan(parentPID: 1, executablePath: "/opt/tool/versions/2.1.284"))
        XCTAssertNil(orphan(parentPID: 1, executablePath: "/Users/me/.local/share/claude/node"))
    }

    func testOrphanedAgentProcessSkipsTerminalSessionsAndOwnQuotaReads() {
        XCTAssertNil(orphan(parentPID: 1, terminalDevice: 0x1000_0003, executablePath: claudePath))
        XCTAssertNil(orphan(parentPID: ProcessInfo.processInfo.processIdentifier, executablePath: claudePath))
    }

    func testOrphanedAgentProcessesIsNilWhenEmpty() {
        XCTAssertNil(OrphanedAgentProcesses([]))
    }

    func testOrphanedAgentProcessesSummarizesCountsPerProviderInOrder() throws {
        let processes = OrphanedAgentProcesses([
            try XCTUnwrap(orphan(parentPID: 1, executablePath: "/Users/me/.codex/bin/codex")),
            try XCTUnwrap(orphan(parentPID: 1, executablePath: claudePath)),
            try XCTUnwrap(orphan(parentPID: 1, executablePath: "/Users/me/.codex/bin/codex")),
        ])

        XCTAssertEqual(processes?.summary, "2 codex, 1 claude")
    }

    private func orphan(
        parentPID: pid_t,
        terminalDevice: UInt32 = OrphanedAgentProcess.noTerminal,
        executablePath: String
    ) -> OrphanedAgentProcess? {
        OrphanedAgentProcess(
            identity,
            parentPID: parentPID,
            terminalDevice: terminalDevice,
            executablePath: executablePath
        )
    }
}
