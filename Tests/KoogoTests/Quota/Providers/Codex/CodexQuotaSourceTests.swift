import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaSourceTests: XCTestCase {
    func testFetchUsesAccountAndNamedWindowsAndClassifiesSwappedWindows() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10584,"resetsAt":1800000000},"secondary":{"usedPercent":45,"windowDurationMins":285,"resetsAt":1700000000}},"rateLimitsByLimitId":{"codex_bengalfox":{"limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},"codex":{"limitName":null,"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1600000000},"secondary":null}},"rateLimitResetCredits":null}}
                """
        )

        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(
            snapshot.windows.map(\.title),
            ["Session", "Weekly", "GPT-5.3-Codex-Spark Session", "GPT-5.3-Codex-Spark Weekly"]
        )
        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 45)
        XCTAssertEqual(
            snapshot.windows["Session"]?.resetsAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(snapshot.windows["Weekly"]?.usedPercent, 15)
        XCTAssertEqual(
            snapshot.windows["Weekly"]?.resetsAt,
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(snapshot.windows["GPT-5.3-Codex-Spark Session"]?.usedPercent, 10)
        XCTAssertEqual(snapshot.windows["GPT-5.3-Codex-Spark Weekly"]?.usedPercent, 20)
    }

    func testFetchDropsEmptyIDsAndTitlesUnnamedWindowsByID() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let window = #"{"usedPercent":10,"windowDurationMins":300}"#
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex"},"rateLimitsByLimitId":{"":{"limitName":"Nameless","primary":\(window)},"id_x":{"limitName":"","primary":\(window)},"id_y":{"limitName":null,"primary":\(window)}}}}
                """
        )

        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows.map(\.title), ["id_x", "id_y"])
    }

    func testFetchOmitsUnknownWindowsAndPreservesKnownZeroResets() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(
                usedPercent: 20,
                windowMinutes: 1_440,
                resetCount: 0,
                credits: "[]"
            )
        )

        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows, [])
        XCTAssertEqual(snapshot.resetCredits?.availableCount, 0)
        XCTAssertEqual(snapshot.resetCredits?.credits, [])
    }

    func testFetchKeepsLimitsWhenResetCreditsAreInvalid() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: -1, credits: "[]")
        )

        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 25)
        XCTAssertNil(snapshot.resetCredits)
    }

    func testCreditsAvailabilityAndHiddenBalance() throws {
        let cases: [(String, QuotaSnapshot.Credits?)] = [
            (#"{"hasCredits":true,"unlimited":false,"balance":" 42.25 "}"#, .balance(amount: 42.25)),
            (#"{"hasCredits":true,"unlimited":false,"balance":"0"}"#, .balance(amount: 0)),
            (#"{"hasCredits":true,"unlimited":false,"balance":null}"#, .available),
            (#"{"hasCredits":true,"unlimited":false,"balance":"unavailable"}"#, .available),
            (#"{"hasCredits":true,"unlimited":false,"balance":"nan"}"#, .available),
            (#"{"hasCredits":false,"unlimited":true,"balance":"12"}"#, .unlimited),
            (#"{"hasCredits":false,"unlimited":false,"balance":"12"}"#, nil),
            ("null", nil),
        ]
        for (credits, expected) in cases {
            let response = try JSONDecoder().decode(
                CodexQuotaResponse.self,
                from: Data(
                    """
                    {"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300},"credits":\(credits)}}
                    """.utf8
                )
            )
            let snapshot = try XCTUnwrap(response.snapshot)

            XCTAssertEqual(snapshot.credits, expected, credits)
            XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 25)
        }
    }

    func testCreditsWithoutWindowsOrBankedResets() throws {
        let response = try JSONDecoder().decode(
            CodexQuotaResponse.self,
            from: Data(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"50"}}}"#.utf8)
        )
        let snapshot = try XCTUnwrap(response.snapshot)

        XCTAssertEqual(snapshot.credits, .balance(amount: 50))
        XCTAssertEqual(snapshot.windows, [])
        XCTAssertNil(snapshot.resetCredits)
    }

    func testFetchReportsEmptyLimitsWhenNoWindowOrCreditSurvives() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 20, windowMinutes: 1_440)
        )

        let result = await CodexQuotaSource(executableCandidates: [executable]).load()

        XCTAssertEqual(result, .unavailable(.emptyLimits))
    }

    func testFetchRejectsResponseContainingResultAndError() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null},"error":{"code":-32603,"message":"invalid response"}}
                """
        )

        let result = await CodexQuotaSource(executableCandidates: [executable]).load()

        XCTAssertEqual(result, .unavailable(.sessionFailed))
    }

    func testFetchAddsLauncherDirectoryToChildPath() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let runtime = try makeTestExecutable(in: workspace.root, script: "#!/bin/sh\nexec /bin/sh \"$@\"\n")
        let executable = try makeTestExecutable(
            in: workspace.root,
            script: """
                #!/usr/bin/env \(runtime.lastPathComponent)
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r initialized
                IFS= read -r rate_limits
                printf '%s\\n' '\(CodexQuotaTestWorkspace.rateLimitsResponse())'
                """
        )

        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 25)
    }

    func testFetchHidesQuotaWhenLauncherClosesInputBeforeHandshake() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try makeTestExecutable(
            in: workspace.root,
            script:
                "#!/bin/sh\nIFS= read -r initialize\nexec 0<&-\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nsleep 1\n"
        )

        let result = await CodexQuotaSource(executableCandidates: [executable]).load()

        XCTAssertEqual(result, .unavailable(.sessionFailed))
    }

    func testFetchReturnsSnapshotWhenServerDoesNotExitAfterResponse() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try makeTestExecutable(
            in: workspace.root,
            script: """
                #!/bin/sh
                trap '' TERM
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r initialized
                IFS= read -r rate_limits
                printf '%s\\n' '\(CodexQuotaTestWorkspace.rateLimitsResponse())'
                while :; do :; done
                """
        )

        let started = ContinuousClock.now
        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.windows["Session"]?.usedPercent, 25)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testCancellationKillsDescendantsSpawnedDuringTerminationGrace() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let readyMarker = workspace.root.appending(path: "ready")
        let childMarker = workspace.root.appending(path: "child")
        let executable = try makeTestExecutable(
            in: workspace.root,
            script: """
                #!/bin/sh
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r initialized
                IFS= read -r rate_limits
                terminate() {
                  (trap '' TERM; sleep 5) &
                  printf '%s\\n' "$!" > '\(childMarker.path)'
                  exit 0
                }
                trap terminate TERM
                printf 'ready\\n' > '\(readyMarker.path)'
                while :; do :; done
                """
        )

        let fetch = Task {
            await CodexQuotaSource(executableCandidates: [executable]).load()
        }
        try await waitUntil(timeout: .seconds(2)) { FileManager.default.fileExists(atPath: readyMarker.path) }

        let cancellationStarted = ContinuousClock.now
        fetch.cancel()
        let result = await fetch.value

        XCTAssertThrowsError(try result.get())
        XCTAssertLessThan(ContinuousClock.now - cancellationStarted, .seconds(3))
        try await waitForExit(pidIn: childMarker)
    }

    func testFetchTimesOutAndKillsStalledServer() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let pidMarker = workspace.root.appending(path: "pid")
        let executable = try makeTestExecutable(
            in: workspace.root,
            script: """
                #!/bin/sh
                printf '%s\\n' "$$" > '\(pidMarker.path)'
                IFS= read -r initialize
                while :; do :; done
                """
        )

        let started = ContinuousClock.now
        let result = await CodexQuotaSource(executableCandidates: [executable], timeout: .milliseconds(500))
            .load()

        XCTAssertEqual(result, .unavailable(.timedOut))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
        try await waitForExit(pidIn: pidMarker)
    }

}
