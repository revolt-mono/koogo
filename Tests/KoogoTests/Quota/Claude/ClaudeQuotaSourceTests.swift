import Foundation
import XCTest

@testable import Koogo

final class ClaudeQuotaSourceTests: XCTestCase {
    func testFetchSendsOneIsolatedUsageRequestAndReadsThePlanWindows() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeCLI()
        let snapshot = try await ClaudeQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.account["Session"]?.remainingPercent, 88)
        XCTAssertEqual(snapshot.account["Session"]?.resetsAt, Date(timeIntervalSince1970: 1_788_220_800.125))
        XCTAssertEqual(snapshot.account["Weekly"]?.remainingPercent, 71)
        XCTAssertEqual(snapshot.account["Weekly"]?.resetsAt, Date(timeIntervalSince1970: 1_788_393_600))
        XCTAssertEqual(snapshot.models.map(\.title), ["Fable"])
        XCTAssertEqual(snapshot.models.first?.windows["Weekly"]?.remainingPercent, 37)
        XCTAssertEqual(snapshot.models.first?.windows["Weekly"]?.resetsAt, Date(timeIntervalSince1970: 1_788_307_200))
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
            XCTAssertEqual(result, .failure(.emptyLimits), limits)
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
            XCTAssertEqual(result, .failure(.sessionFailed), output)
        }
        let executable = try workspace.makeCLI(beforeOutput: "exit 1")
        let result = await ClaudeQuotaSource(executableCandidates: [executable]).load()
        XCTAssertEqual(result, .failure(.sessionFailed))
    }

    func testWindowsClampPercentAndUnstartedOrUnnamedModelWindowsAreSkipped() async throws {
        let workspace = ClaudeQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let limits = """
            {"five_hour":{"utilization":-8,"resets_at":null},"seven_day":{"utilization":130},\
            "model_scoped":[\
            {"display_name":"Other model","utilization":3.9,"resets_at":null},\
            {"display_name":" ","utilization":1,"resets_at":null},\
            {"display_name":"Unstarted","utilization":null,"resets_at":null}]}
            """
        let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
        let snapshot = try await ClaudeQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.account["Session"]?.remainingPercent, 100)
        XCTAssertNil(snapshot.account["Session"]?.resetsAt)
        XCTAssertEqual(snapshot.account["Weekly"]?.remainingPercent, 0)
        XCTAssertEqual(snapshot.models.map(\.title), ["Other model"])
        XCTAssertEqual(snapshot.models.first?.windows["Weekly"]?.remainingPercent, 97)
    }

    func testFetchReportsMissingExecutable() async throws {
        let root = try makeTemporaryDirectory()
        let notExecutable = root.appending(path: "claude")
        try Data().write(to: notExecutable)
        let result = await ClaudeQuotaSource(executableCandidates: [root.appending(path: "missing"), notExecutable])
            .load()
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
                await ClaudeQuotaSource(
                    executableCandidates: [executable],
                    timeout: cancel ? .seconds(15) : .seconds(1)
                )
                .load()
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
