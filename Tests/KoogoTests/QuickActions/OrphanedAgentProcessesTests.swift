import Foundation
import Testing

@testable import Koogo

struct OrphanedAgentProcessesTests {
  @Test
  func `orphaned agent process recognizes agent executables without a terminal`() {
    let orphans = [
      claudePath,
      "/Users/me/.codex/packages/standalone/releases/0.158.0-aarch64-apple-darwin/bin/codex",
      "/Users/me/.grok/downloads/grok-1.0.45-macos-aarch64",
    ].map { orphan(parentPID: 1, executablePath: $0)?.provider }

    #expect(orphans == [.claude, .codex, .grok])
    #expect(orphan(parentPID: 900, executablePath: claudePath) != nil, "daemon children count without launchd")
    #expect(orphan(parentPID: 1, executablePath: "/opt/tool/versions/2.1.284") == nil)
    #expect(orphan(parentPID: 1, executablePath: "/Users/me/.local/share/claude/node") == nil)
  }

  @Test
  func `orphaned agent process skips terminal sessions and own quota reads`() {
    #expect(orphan(parentPID: 1, hasTerminal: true, executablePath: claudePath) == nil)
    #expect(orphan(parentPID: ProcessInfo.processInfo.processIdentifier, executablePath: claudePath) == nil)
  }

  @Test
  func `orphaned agent processes summarizes counts per provider in order`() throws {
    let processes = OrphanedAgentProcesses([
      try #require(orphan(parentPID: 1, executablePath: "/Users/me/.codex/bin/codex")),
      try #require(orphan(parentPID: 1, executablePath: claudePath)),
      try #require(orphan(parentPID: 1, executablePath: "/Users/me/.codex/bin/codex")),
    ])

    #expect(processes?.summary == "2 codex, 1 claude")
  }

  private let identity = ProcessIdentity(pid: 42, startTicks: 0)
  private let claudePath = "/Users/me/.local/share/claude/versions/2.1.284"

  private func orphan(
    parentPID: pid_t,
    hasTerminal: Bool = false,
    executablePath: String,
  ) -> OrphanedAgentProcess? {
    OrphanedAgentProcess(
      identity,
      parentPID: parentPID,
      hasTerminal: hasTerminal,
      executablePath: executablePath,
    )
  }
}
