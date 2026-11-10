import XCTest

@testable import Koogo

final class LingeringAppsTests: XCTestCase {
    func testLingeringAppNeedsAProcessToStopAndSparesTheAppKoogoRunsUnder() {
        XCTAssertNil(app("Notes", processes: []))
        XCTAssertNil(app("Terminal", processes: [(7, "zsh"), (ProcessInfo.processInfo.processIdentifier, "Koogo")]))
    }

    func testLingeringAppsSummarizesProcessNamesPerApp() throws {
        let apps = LingeringApps([
            try XCTUnwrap(app("Cursor", processes: [(7, "cursor-agent"), (8, "chrome_crashpad_handler")])),
            try XCTUnwrap(app("Terminal", processes: [(9, "zsh"), (10, "zsh")])),
        ])

        XCTAssertEqual(apps?.summary, "Cursor (chrome_crashpad_handler, cursor-agent), Terminal (zsh)")
    }

    private func app(_ name: String, processes: [(pid: pid_t, name: String)]) -> LingeringApp? {
        LingeringApp(
            serialNumber: name as CFString,
            name: name,
            processes: processes.map { (ProcessIdentity(pid: $0.pid, startTicks: 0), $0.name) }
        )
    }
}
