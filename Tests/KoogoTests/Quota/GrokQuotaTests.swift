import Foundation
import Synchronization
import XCTest

@testable import Koogo

final class GrokQuotaTests: XCTestCase {
    private var root: URL!
    private var authURL: URL { root.appending(path: "auth.json") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testFetchSendsTheCLISessionAndReadsTheWeeklyLimit() async throws {
        try writeSession(expiresAt: "2999-01-01T00:00:00.123456Z")
        let requests = Mutex<[URLRequest]>([])
        let service = GrokQuotaService(authURL: authURL) { request in
            requests.withLock { $0.append(request) }
            return try Self.reply(
                """
                {"config":{"creditUsagePercent":3.9,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
                "start":"2026-09-20T18:33:16.478027+00:00","end":"2026-09-27T18:33:16.478027+00:00"},\
                "prepaidBalance":{},"isUnifiedBillingUser":true},"productUsage":[]}
                """
            )
        }

        let snapshot = try await service.fetch().get()

        XCTAssertEqual(snapshot.period, .weekly)
        XCTAssertEqual(snapshot.window.remainingPercent, 97)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.window.resetsAt).timeIntervalSince1970,
            1_790_533_996.478,
            accuracy: 0.001
        )
        let request = try XCTUnwrap(requests.withLock { $0.first })
        XCTAssertEqual(request.url?.absoluteString, "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-userid"), "user-1")
    }

    func testUntouchedQuotaIsFullAndMonthlyPeriodsAreKept() async throws {
        try writeSession(expiresAt: nil)
        let service = GrokQuotaService(authURL: authURL) { _ in
            try Self.reply(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}"#)
        }

        let result = await service.fetch()

        XCTAssertEqual(
            result,
            .success(GrokQuotaSnapshot(period: .monthly, window: QuotaWindow(usedPercent: 0, resetsAt: nil)))
        )
    }

    func testMissingAndExpiredSessionsNeverReachTheNetwork() async throws {
        let service = GrokQuotaService(authURL: authURL) { _ in
            XCTFail("unexpected request")
            throw URLError(.badURL)
        }

        let missing = await service.fetch()
        try Data(#"{"xai::api_key":{"key":"xai-key","auth_mode":"api_key"}}"#.utf8).write(to: authURL)
        let apiKey = await service.fetch()
        try writeSession(expiresAt: "2000-01-01T00:00:00Z")
        let expired = await service.fetch()

        XCTAssertEqual(missing, .failure(.signedOut))
        XCTAssertEqual(apiKey, .failure(.signedOut))
        XCTAssertEqual(expired, .failure(.credentialsExpired))
    }

    func testRejectedRequestsAndEmptyConfigsAreUnavailable() async throws {
        try writeSession(expiresAt: "2999-01-01T00:00:00Z")
        let rejected = GrokQuotaService(authURL: authURL) { _ in
            try Self.reply(#"{"error":"unauthorized"}"#, status: 401)
        }
        let empty = GrokQuotaService(authURL: authURL) { _ in try Self.reply(#"{"config":null}"#) }

        let rejectedResult = await rejected.fetch()
        let emptyResult = await empty.fetch()

        XCTAssertEqual(rejectedResult, .failure(.requestFailed))
        XCTAssertEqual(emptyResult, .failure(.emptyLimits))
    }

    @MainActor
    func testModelKeepsTheLastSnapshotOnceTheSessionExpires() async throws {
        let model = GrokQuotaModel(
            quotaService: GrokQuotaService(authURL: authURL) { _ in
                try Self.reply(#"{"config":{"creditUsagePercent":25}}"#)
            },
            cooldown: .zero
        )

        try writeSession(expiresAt: "2000-01-01T00:00:00Z")
        try await refresh(model)
        XCTAssertEqual(model.state, .unavailable)
        XCTAssertEqual(model.refreshFailure, .credentialsExpired)

        try writeSession(expiresAt: "2999-01-01T00:00:00Z")
        try await refresh(model)
        let snapshot = GrokQuotaSnapshot(period: nil, window: QuotaWindow(usedPercent: 25, resetsAt: nil))
        XCTAssertEqual(model.state, .available(snapshot))
        XCTAssertNil(model.refreshFailure)

        try writeSession(expiresAt: "2000-01-01T00:00:00Z")
        try await refresh(model)
        XCTAssertEqual(model.state, .available(snapshot))
        XCTAssertEqual(model.refreshFailure, .credentialsExpired)
    }

    @MainActor
    private func refresh(_ model: GrokQuotaModel) async throws {
        model.refresh()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isRefreshing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isRefreshing)
    }

    private func writeSession(expiresAt: String?) throws {
        let expiry = expiresAt.map { #","expires_at":"\#($0)""# } ?? ""
        try Data(
            """
            {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"access-token","auth_mode":"oidc",\
            "create_time":"2026-09-24T13:51:26.374406Z","user_id":"user-1","refresh_token":"refresh"\(expiry)}}
            """.utf8
        )
        .write(to: authURL)
    }

    private static func reply(_ body: String, status: Int = 200) throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(URL(string: "https://cli-chat-proxy.grok.com/v1/billing"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }
}
