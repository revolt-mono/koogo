import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaServiceTests: XCTestCase {
    func testFetchUsesAccountAndModelLimitsAndClassifiesSwappedWindows() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10584,"resetsAt":1800000000},"secondary":{"usedPercent":45,"windowDurationMins":285,"resetsAt":1700000000}},"rateLimitsByLimitId":{"codex_bengalfox":{"limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},"codex":{"limitName":null,"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1600000000},"secondary":null}},"rateLimitResetCredits":null}}
                """
        )

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.models.map(\.id), ["codex_bengalfox"])
        XCTAssertEqual(snapshot.models[0].title, "GPT-5.3-Codex-Spark")

        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 55)
        XCTAssertEqual(
            snapshot.account?.limits?.fiveHour?.resetsAt,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(snapshot.account?.limits?.weekly?.remainingPercent, 85)
        XCTAssertEqual(
            snapshot.account?.limits?.weekly?.resetsAt,
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(snapshot.models[0].limits.fiveHour?.remainingPercent, 90)
        XCTAssertEqual(snapshot.models[0].limits.weekly?.remainingPercent, 80)
    }

    func testFetchNamesReserveQuotaWithoutChangingItsIdentityOrWindows() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex"},"rateLimitsByLimitId":{"base_model_inference":{"limitName":"gpt-reserve","primary":{"usedPercent":48,"windowDurationMins":10080,"resetsAt":1800000000}}}}}
                """
        )

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()
        let model = try XCTUnwrap(snapshot.models.first)

        XCTAssertEqual(snapshot.models.count, 1)
        XCTAssertEqual(model.id, "base_model_inference")
        XCTAssertEqual(model.title, "Reserve quota")
        XCTAssertNil(model.limits.fiveHour)
        XCTAssertEqual(model.limits.weekly?.remainingPercent, 52)
        XCTAssertEqual(model.limits.weekly?.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testFetchDropsEmptyModelIDsAndTitlesUntitledModelsByID() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let window = #"{"usedPercent":10,"windowDurationMins":300}"#
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex"},"rateLimitsByLimitId":{"":{"limitName":"Nameless","primary":\(window)},"model_x":{"limitName":"","primary":\(window)},"model_y":{"limitName":null,"primary":\(window)}}}}
                """
        )

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.models.map(\.id), ["model_x", "model_y"])
        XCTAssertEqual(snapshot.models.map(\.title), ["model_x", "model_y"])
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

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertNil(snapshot.account?.limits)
        XCTAssertEqual(snapshot.account?.resetCredits?.availableCount, 0)
        XCTAssertEqual(snapshot.account?.resetCredits?.credits, [])
        XCTAssertTrue(snapshot.models.isEmpty)
    }

    func testFetchKeepsLimitsWhenResetCreditsAreInvalid() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: -1, credits: "[]")
        )

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 75)
        XCTAssertNil(snapshot.account?.resetCredits)
    }

    func testFetchReportsEmptyLimitsWhenNoWindowOrCreditSurvives() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 20, windowMinutes: 1_440)
        )

        let result = await CodexQuotaService(executableCandidates: [executable]).fetch()

        XCTAssertEqual(result, .failure(.emptyLimits))
    }

    func testFetchRejectsResponseContainingResultAndError() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAppServer(
            quotaResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null},"error":{"code":-32603,"message":"invalid response"}}
                """
        )

        let result = await CodexQuotaService(executableCandidates: [executable]).fetch()

        XCTAssertEqual(result, .failure(.sessionFailed))
    }

    func testFetchAddsLauncherDirectoryToChildPath() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let runtime = try workspace.makeExecutable(script: "#!/bin/sh\nexec /bin/sh \"$@\"\n")
        let executable = try workspace.makeExecutable(
            script: """
                #!/usr/bin/env \(runtime.lastPathComponent)
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"result":{}}'
                IFS= read -r initialized
                IFS= read -r rate_limits
                printf '%s\\n' '\(CodexQuotaTestWorkspace.rateLimitsResponse())'
                """
        )

        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 75)
    }

    func testFetchHidesQuotaWhenLauncherClosesInputBeforeHandshake() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeExecutable(
            script:
                "#!/bin/sh\nIFS= read -r initialize\nexec 0<&-\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nsleep 1\n"
        )

        let result = await CodexQuotaService(executableCandidates: [executable]).fetch()

        XCTAssertEqual(result, .failure(.sessionFailed))
    }

    func testFetchReturnsSnapshotWhenServerDoesNotExitAfterResponse() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeExecutable(
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
        let snapshot = try await CodexQuotaService(executableCandidates: [executable]).fetch().get()

        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 75)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testCancellationKillsDescendantsSpawnedDuringTerminationGrace() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let readyMarker = workspace.root.appending(path: "ready")
        let childMarker = workspace.root.appending(path: "child")
        let executable = try workspace.makeExecutable(
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
            await CodexQuotaService(executableCandidates: [executable]).fetch()
        }
        try await waitUntil(timeout: .seconds(2)) { FileManager.default.fileExists(atPath: readyMarker.path) }

        let cancellationStarted = ContinuousClock.now
        fetch.cancel()
        let result = await fetch.value

        XCTAssertThrowsError(try result.get())
        XCTAssertLessThan(ContinuousClock.now - cancellationStarted, .seconds(3))
        try await waitForExit(pidWrittenTo: childMarker)
    }

    func testFetchTimesOutAndKillsStalledServer() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let pidMarker = workspace.root.appending(path: "pid")
        let executable = try workspace.makeExecutable(
            script: """
                #!/bin/sh
                printf '%s\\n' "$$" > '\(pidMarker.path)'
                IFS= read -r initialize
                while :; do :; done
                """
        )

        let started = ContinuousClock.now
        let result = await CodexQuotaService(executableCandidates: [executable], timeout: .milliseconds(500))
            .fetch()

        XCTAssertEqual(result, .failure(.timedOut))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
        try await waitForExit(pidWrittenTo: pidMarker)
    }

    func testFetchReportsMissingBinaryWhenNoCandidateIsExecutable() async throws {
        let root = try makeTemporaryDirectory()
        let notExecutable = root.appending(path: "codex")
        try Data().write(to: notExecutable)

        let result = await CodexQuotaService(
            executableCandidates: [root.appending(path: "missing/codex"), notExecutable]
        )
        .fetch()

        XCTAssertEqual(result, .failure(.binaryNotFound))
    }

    /// Reads a pid a stub server wrote to `marker` and asserts that the process is gone within three seconds.
    private func waitForExit(
        pidWrittenTo marker: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let contents = try String(contentsOf: marker, encoding: .utf8)
        let pid = try XCTUnwrap(pid_t(contents.trimmingCharacters(in: .newlines)), file: file, line: line)
        try await waitUntil(timeout: .seconds(3), file: file, line: line) { kill(pid, 0) == -1 && errno == ESRCH }
    }
}
