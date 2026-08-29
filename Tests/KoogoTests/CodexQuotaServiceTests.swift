import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testQuotaTimeRemainingUsesLargestAllowedUnit() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cases: [(TimeInterval, String)] = [
            (2 * 86_400, "in 2 days"),
            (86_400, "in 1 day"),
            (23 * 3_600, "in 23h"),
            (3_600, "in 1h"),
            (59 * 60, "in 59m"),
            (60, "in 1m"),
            (59, "soon"),
            (-1, "soon"),
        ]

        for (interval, expected) in cases {
            XCTAssertEqual(
                quotaTimeRemainingText(until: now.addingTimeInterval(interval), now: now),
                expected
            )
        }
    }

    func testFetchUsesAccountAndModelLimitsAndClassifiesSwappedWindows() async throws {
        let executable = try makeExecutable(
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
        let executable = try makeExecutable(
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
        let executable = try makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":-1,"credits":[]}}}
                """
        )

        let snapshot = await CodexQuotaService(executableURL: executable).fetch()

        XCTAssertEqual(snapshot?.account?.limits?.fiveHour?.remainingPercent, 75)
        XCTAssertNil(snapshot?.account?.resetCredits)
    }

    func testFetchRejectsResponseContainingResultAndError() async throws {
        let executable = try makeExecutable(
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
        let executable = try makeExecutable(
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

    @MainActor
    func testQuotaModelCoalescesAndCachesRefreshes() async throws {
        let launches = root.appending(path: "launches")
        let executable = try makeExecutable(
            launchMarker: launches,
            responseDelay: 0.2,
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableURL: executable)
        )

        model.refresh()
        model.refresh()
        XCTAssertEqual(model.state, .loading)

        let deadline = ContinuousClock.now + .seconds(2)
        while model.state == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        guard case .available(let snapshot) = model.state else {
            return XCTFail("expected available quota")
        }
        XCTAssertEqual(snapshot.account?.limits?.fiveHour?.remainingPercent, 75)
        model.refresh()
        try await Task.sleep(for: .milliseconds(100))

        let launchCount = try String(contentsOf: launches, encoding: .utf8)
            .split(separator: "\n")
            .count
        XCTAssertEqual(launchCount, 1)
    }

    @MainActor
    func testQuotaModelKeepsExistingSnapshotUntilFailedRefreshCompletes() async throws {
        let executable = try makeExecutable(
            rateLimitsResponse: """
                {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1700000000},"secondary":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
                """
        )
        let model = CodexQuotaModel(
            quotaService: CodexQuotaService(executableURL: executable),
            refreshInterval: .zero
        )
        model.refresh()
        var deadline = ContinuousClock.now + .seconds(2)
        while model.state == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .available(let snapshot) = model.state else {
            return XCTFail("expected available quota")
        }

        try FileManager.default.removeItem(at: executable)
        model.refresh()
        XCTAssertEqual(model.state, .available(snapshot))
        deadline = ContinuousClock.now + .seconds(2)
        while model.state != .hidden, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.state, .hidden)
    }

    private func makeExecutable(
        shebang: String = "#!/bin/sh",
        launchMarker: URL? = nil,
        responseDelay: TimeInterval = 0,
        rateLimitsResponse: String
    ) throws -> URL {
        let executable = root.appending(path: UUID().uuidString)
        let launchLine = launchMarker.map { "printf 'launch\\n' >> '\($0.path)'" } ?? ":"
        let script = """
            \(shebang)
            \(launchLine)
            IFS= read -r initialize
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r initialized
            IFS= read -r rate_limits
            printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
            sleep \(responseDelay)
            printf '%s\\n' '\(rateLimitsResponse)'
            """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return executable
    }
}
