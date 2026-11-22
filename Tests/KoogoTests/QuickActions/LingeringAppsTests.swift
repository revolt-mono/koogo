import Foundation
import Testing

@testable import Koogo

struct LingeringAppsTests {
  @Test
  func `lingering app needs a process to stop and spares the app koogo runs under`() {
    #expect(app("Notes", processes: []) == nil)
    #expect(app("Terminal", processes: [(7, "zsh"), (ProcessInfo.processInfo.processIdentifier, "Koogo")]) == nil)
  }

  @Test
  func `lingering apps summarizes process names per app`() throws {
    let apps = LingeringApps([
      try #require(app("Cursor", processes: [(7, "cursor-agent"), (8, "chrome_crashpad_handler")])),
      try #require(app("Terminal", processes: [(9, "zsh"), (10, "zsh")])),
    ])

    #expect(apps?.summary == "Cursor (chrome_crashpad_handler, cursor-agent), Terminal (zsh)")
  }

  private func app(_ name: String, processes: [(pid: pid_t, name: String)]) -> LingeringApp? {
    LingeringApp(
      serialNumber: name as CFString,
      name: name,
      processes: processes.map {
        LingeringApp.RemainingProcess(identity: ProcessIdentity(pid: $0.pid, startTicks: 0), name: $0.name)
      },
    )
  }
}
