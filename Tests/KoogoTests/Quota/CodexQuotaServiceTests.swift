import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaServiceTests: XCTestCase {
    private var workspace: CodexQuotaTestWorkspace!
    private var root: URL { workspace.root }

    override func setUpWithError() throws {
        workspace = try CodexQuotaTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    func testFetchUsesAccountAndModelLimitsAndClassifiesSwappedWindows() async throws {
        let executable = try workspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10584,"resetsAt":1800000000},"secondary":{"usedPercent":45,"windowDurationMins":285,"resetsAt":1700000000}},"rateLimitsByLimitId":{"codex_bengalfox":{"limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},"codex":{"limitName":null,"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1600000000},"secondary":null}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"status":"available","expiresAt":2100000000},{"status":"future_status","expiresAt":1900000000},{"status":"available","expiresAt":2000000000}]}}}
                """
        )

        guard let snapshot = await CodexQuotaService(executableURL: executable).fetch() else {
            return XCTFail("expected available quota")
        }
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
        XCTAssertEqual(snapshot.account?.resetCredits?.availableCount, 2)
        XCTAssertEqual(
            snapshot.account?.resetCredits?.nextExpiration,
            Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    func testFetchOmitsUnknownWindowsAndPreservesKnownZeroResets() async throws {
        let executable = try workspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":1440,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":0,"credits":[]}}}
                """
        )

        guard let snapshot = await CodexQuotaService(executableURL: executable).fetch() else {
            return XCTFail("expected available quota")
        }
        XCTAssertNil(snapshot.account?.limits)
        XCTAssertEqual(snapshot.account?.resetCredits?.availableCount, 0)
        XCTAssertNil(snapshot.account?.resetCredits?.nextExpiration)
        XCTAssertTrue(snapshot.models.isEmpty)
    }

    func testFetchKeepsLimitsWhenResetCreditsAreInvalid() async throws {
        let executable = try workspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":-1,"credits":[]}}}
                """
        )

        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertEqual(snapshot?.account?.limits?.fiveHour?.remainingPercent, 75)
        XCTAssertNil(snapshot?.account?.resetCredits)
    }

    func testFetchRejectsResponseContainingResultAndError() async throws {
        let executable = try workspace.makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null},"error":{"code":-32603,"message":"invalid response"}}
                """
        )

        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertNil(snapshot)
    }

    func testFetchAddsLauncherDirectoryToChildPath() async throws {
        let runtime = root.appending(path: "koogo-test-runtime")
        try "#!/bin/sh\nexec /bin/sh \"$@\"\n".write(
            to: runtime,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runtime.path
        )
        let executable = try workspace.makeExecutable(
            shebang: "#!/usr/bin/env koogo-test-runtime",
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )

        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertEqual(snapshot?.account?.limits?.fiveHour?.remainingPercent, 75)
    }

    func testFetchHidesQuotaWhenLauncherClosesInputBeforeHandshake() async throws {
        let executable = root.appending(path: UUID().uuidString)
        try "#!/bin/sh\nIFS= read -r initialize\nexec 0<&-\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nsleep 1\n"
            .write(
                to: executable,
                atomically: true,
                encoding: .utf8
            )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertNil(snapshot)
    }

    func testFetchReturnsSnapshotWhenServerDoesNotExitAfterResponse() async throws {
        let executable = root.appending(path: UUID().uuidString)
        try """
        #!/bin/sh
        trap '' TERM
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r rate_limits
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}'
        while :; do :; done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let started = ContinuousClock.now
        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertEqual(snapshot?.account?.limits?.fiveHour?.remainingPercent, 75)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(3))
    }

    func testCancellationKillsDescendantsSpawnedDuringTerminationGrace() async throws {
        let readyMarker = root.appending(path: "ready")
        let childMarker = root.appending(path: "child")
        let executable = root.appending(path: UUID().uuidString)
        try """
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
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let fetch = Task {
            await CodexQuotaService(executableURL: executable).fetch()
        }
        let markerDeadline = ContinuousClock.now + .seconds(2)
        while !FileManager.default.fileExists(atPath: readyMarker.path),
            ContinuousClock.now < markerDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: readyMarker.path))

        let cancellationStarted = ContinuousClock.now
        fetch.cancel()
        let snapshot = await fetch.value

        XCTAssertNil(snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: childMarker.path))
        XCTAssertLessThan(ContinuousClock.now - cancellationStarted, .seconds(3))
    }
}
