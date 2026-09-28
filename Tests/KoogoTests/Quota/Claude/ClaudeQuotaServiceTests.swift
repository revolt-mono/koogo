import Foundation
import XCTest

@testable import Koogo

final class ClaudeQuotaServiceTests: XCTestCase {
    func testFetchRunsOnlyIsolatedUsageCommand() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeCLI()
        let snapshot = try await ClaudeQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.account?.session?.remainingPercent, 88)
        XCTAssertEqual(snapshot.account?.session?.resetsAt, Date(timeIntervalSince1970: 1_788_220_800.125))
        XCTAssertEqual(snapshot.account?.weekly?.remainingPercent, 71)
        XCTAssertEqual(snapshot.account?.weekly?.resetsAt, Date(timeIntervalSince1970: 1_788_393_600))
        XCTAssertEqual(snapshot.models.map(\.title), ["Fable"])
        XCTAssertEqual(snapshot.models.first?.limits.weekly?.remainingPercent, 37)
        XCTAssertEqual(snapshot.models.first?.limits.weekly?.resetsAt, Date(timeIntervalSince1970: 1_788_307_200))
        let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8)
        XCTAssertEqual(
            arguments.components(separatedBy: "\n"),
            [
                "--setting-sources", "", "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
                "--strict-mcp-config", "--tools", "", "--no-session-persistence", "--max-budget-usd", "0.01",
                "-p", "/usage", "--output-format", "stream-json", "--verbose", "",
            ]
        )
        XCTAssertEqual(try String(contentsOf: workspace.callsFile, encoding: .utf8), "usage\n")
    }

    func testEmptyLimitsAreDistinctFromInvalidOrUnsuccessfulOutput() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        for limits in ["null", #"{"limits":null}"#, #"{"limits":[]}"#, #"{"limits":[{"kind":"future_limit"}]}"#] {
            let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
            let result = await ClaudeQuotaService(executableCandidates: [executable]).fetch()
            XCTAssertEqual(result, .failure(.emptyLimits))
        }
        for output in [
            "not json",
            #"{"type":"result","subtype":"success","is_error":false,"result":"12% used"}"#,
            #"{"type":"assistant","usage_report":{"rate_limits":null}}"#,
            ClaudeQuotaTestWorkspace.response().replacingOccurrences(
                of: "\"is_error\":false",
                with: "\"is_error\":true"
            ),
            ClaudeQuotaTestWorkspace.response(rateLimits: #"{"limits":[{"kind":"session"}]}"#),
            ClaudeQuotaTestWorkspace.response(
                rateLimits: #"{"limits":[{"kind":"session","percent":5,"resets_at":"not a date"}]}"#
            ),
        ] {
            let executable = try workspace.makeCLI(output: output)
            let result = await ClaudeQuotaService(executableCandidates: [executable]).fetch()
            XCTAssertEqual(result, .failure(.sessionFailed))
        }
        let executable = try workspace.makeCLI(afterOutput: "exit 1")
        let result = await ClaudeQuotaService(executableCandidates: [executable]).fetch()
        XCTAssertEqual(result, .failure(.sessionFailed))
    }

    func testPartialLimitsClampPercentAndNeverPromoteScopedQuotaToAccountQuota() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let limits = """
            {"limits":[
            {"kind":"session","percent":-8},
            {"kind":"weekly_all","percent":130},
            {"kind":"weekly_scoped","percent":3.9,"scope":{"model":{"display_name":"Other model"}}},
            {"kind":"weekly_scoped","percent":2,"scope":null},
            {"kind":"weekly_scoped","percent":1,"scope":{"model":{"display_name":" "}}},
            {"kind":"weekly_all","percent":4,"scope":{"model":{"display_name":"Scoped"}}},
            {"kind":"session","percent":6,"scope":{"surface":"web"}}
            ]}
            """.replacingOccurrences(of: "\n", with: "")
        let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
        let snapshot = try await ClaudeQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.account?.session?.remainingPercent, 100)
        XCTAssertNil(snapshot.account?.session?.resetsAt)
        XCTAssertEqual(snapshot.account?.weekly?.remainingPercent, 0)
        XCTAssertEqual(snapshot.models.map(\.title), ["Other model"])
        XCTAssertEqual(snapshot.models.first?.limits.weekly?.remainingPercent, 97)
    }

    func testFetchReportsMissingExecutable() async throws {
        let root = try makeTemporaryDirectory()
        let notExecutable = root.appending(path: "claude")
        try Data().write(to: notExecutable)
        let result = await ClaudeQuotaService(executableCandidates: [root.appending(path: "missing"), notExecutable])
            .fetch()
        XCTAssertEqual(result, .failure(.binaryNotFound))
    }

    func testTimeoutAndCancellationStopCLIAndDescendants() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let parentMarker = workspace.root.appending(path: "parent")
        let childMarker = workspace.root.appending(path: "child")
        for cancel in [false, true] {
            let executable = try workspace.makeCLI(
                beforeOutput: """
                    trap '' TERM
                    printf '%s' "$$" > '\(parentMarker.path)'
                    /bin/sleep 30 &
                    printf '%s' "$!" > '\(childMarker.path)'
                    wait
                    """
            )
            let fetch = Task {
                await ClaudeQuotaService(
                    executableCandidates: [executable],
                    timeout: cancel ? .seconds(15) : .seconds(1)
                )
                .fetch()
            }
            try await waitUntil { FileManager.default.fileExists(atPath: childMarker.path) }
            if cancel { fetch.cancel() }
            let result = await fetch.value
            XCTAssertEqual(result, .failure(cancel ? .sessionFailed : .timedOut))
            for marker in [parentMarker, childMarker] {
                let processID = try XCTUnwrap(Int32(String(contentsOf: marker, encoding: .utf8)))
                try await waitUntil { kill(processID, 0) == -1 && errno == ESRCH }
                try FileManager.default.removeItem(at: marker)
            }
        }
    }
}
