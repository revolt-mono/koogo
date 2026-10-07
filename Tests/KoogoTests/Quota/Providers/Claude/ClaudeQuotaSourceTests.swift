import Foundation
import XCTest

@testable import Koogo

final class ClaudeQuotaSourceTests: XCTestCase {
    func testFetchSendsOneIsolatedUsageRequestAndReadsThePlanWindows() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeCLI()
        let snapshot = try await ClaudeQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 12)
        XCTAssertEqual(snapshot.windows["Session"]?.resetsAt, Date(timeIntervalSince1970: 1_788_220_800.125))
        XCTAssertEqual(snapshot.windows["Weekly"]?.usedPercent, 29)
        XCTAssertEqual(snapshot.windows["Weekly"]?.resetsAt, Date(timeIntervalSince1970: 1_788_393_600))
        XCTAssertEqual(snapshot.windows.map(\.title), ["Session", "Weekly", "Fable"])
        XCTAssertEqual(snapshot.windows["Fable"]?.usedPercent, 63)
        XCTAssertEqual(snapshot.windows["Fable"]?.resetsAt, Date(timeIntervalSince1970: 1_788_307_200))
        let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8)
        XCTAssertEqual(
            arguments.components(separatedBy: "\n"),
            [
                "--setting-sources", "", "--settings", #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
                "--strict-mcp-config", "--tools", "", "--no-session-persistence",
                "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "",
            ]
        )
        let directory = try String(contentsOf: workspace.directoryFile, encoding: .utf8).trimmingCharacters(
            in: .newlines
        )
        XCTAssertEqual(
            URL(filePath: directory).resolvingSymlinksInPath(),
            URL(filePath: "/tmp").resolvingSymlinksInPath()
        )
        let lines = try String(contentsOf: workspace.requestsFile, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(request["type"] as? String, "control_request")
        XCTAssertEqual(request["request_id"] as? String, "1")
        XCTAssertEqual(request["request"] as? NSDictionary, ["subtype": "get_usage", "skip_behaviors": true])
    }

    func testEmptyLimitsAreDistinctFromInvalidOrUnansweredOutput() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        for limits in [
            "null", "{}",
            #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":null,"model_scoped":[]}"#,
        ] {
            let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
            let result = await ClaudeQuotaSource(executableCandidates: [executable]).load()
            XCTAssertEqual(result, .unavailable(.emptyLimits), limits)
        }
        for output in [
            "not json",
            #"{"type":"system","subtype":"init"}"#,
            #"{"type":"control_response","response":{"subtype":"error","request_id":"1","error":"nope"}}"#,
            ClaudeQuotaTestWorkspace.response(
                rateLimits: #"{"five_hour":{"utilization":5,"resets_at":"not a date"}}"#
            ),
        ] {
            let executable = try workspace.makeCLI(output: output)
            let result = await ClaudeQuotaSource(executableCandidates: [executable]).load()
            XCTAssertEqual(result, .unavailable(.sessionFailed), output)
        }
        let executable = try workspace.makeCLI(beforeOutput: "exit 1")
        let result = await ClaudeQuotaSource(executableCandidates: [executable]).load()
        XCTAssertEqual(result, .unavailable(.sessionFailed))
    }

    func testWindowsClampPercentAndUnstartedOrUnnamedWindowsAreSkipped() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let limits = """
            {"five_hour":{"utilization":-8,"resets_at":null},"seven_day":{"utilization":130},\
            "model_scoped":[\
            {"display_name":"Other","utilization":3.9,"resets_at":null},\
            {"display_name":" ","utilization":1,"resets_at":null},\
            {"display_name":"Unstarted","utilization":null,"resets_at":null}]}
            """
        let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
        let snapshot = try await ClaudeQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 0)
        XCTAssertNil(snapshot.windows["Session"]?.resetsAt)
        XCTAssertEqual(snapshot.windows["Weekly"]?.usedPercent, 100)
        XCTAssertEqual(snapshot.windows.map(\.title), ["Session", "Weekly", "Other"])
        XCTAssertEqual(snapshot.windows["Other"]?.usedPercent, 3)
    }

    func testFetchReportsMissingExecutable() async throws {
        let root = try makeTemporaryDirectory()
        let notExecutable = root.appending(path: "claude")
        try Data().write(to: notExecutable)
        let result = await ClaudeQuotaSource(executableCandidates: [root.appending(path: "missing"), notExecutable])
            .load()
        XCTAssertEqual(result, .unavailable(.binaryNotFound))
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
                await ClaudeQuotaSource(
                    executableCandidates: [executable],
                    timeout: cancel ? .seconds(15) : .seconds(1)
                )
                .load()
            }
            try await waitUntil { FileManager.default.fileExists(atPath: childMarker.path) }
            if cancel { fetch.cancel() }
            let result = await fetch.value
            XCTAssertEqual(result, .unavailable(cancel ? .sessionFailed : .timedOut))
            for marker in [parentMarker, childMarker] {
                try await waitForExit(pidIn: marker)
                try FileManager.default.removeItem(at: marker)
            }
        }
    }
}
