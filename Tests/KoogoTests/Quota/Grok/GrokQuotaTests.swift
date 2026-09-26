import Foundation
import Synchronization
import XCTest

@testable import Koogo

final class GrokQuotaTests: XCTestCase {
    func testFetchSendsTheCLISessionAndReadsTheWeeklyLimit() async throws {
        let authURL = try makeAuthURL()
        try writeGrokSession(expiresAt: "2999-01-01T00:00:00.123456Z", to: authURL)
        let requests = Mutex<[URLRequest]>([])
        let service = GrokQuotaService(authURL: authURL) { request in
            requests.withLock { $0.append(request) }
            return try grokBillingReply(
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
        let authURL = try makeAuthURL()
        try writeGrokSession(expiresAt: nil, to: authURL)
        let service = GrokQuotaService(authURL: authURL) { _ in
            try grokBillingReply(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}"#)
        }

        let result = await service.fetch()

        XCTAssertEqual(
            result,
            .success(GrokQuotaSnapshot(period: .monthly, window: QuotaWindow(usedPercent: 0, resetsAt: nil)))
        )
    }

    func testMissingAndExpiredSessionsNeverReachTheNetwork() async throws {
        let authURL = try makeAuthURL()
        let service = GrokQuotaService(authURL: authURL) { _ in
            XCTFail("unexpected request")
            throw URLError(.badURL)
        }

        let missing = await service.fetch()
        try Data(#"{"xai::api_key":{"key":"xai-key","auth_mode":"api_key"}}"#.utf8).write(to: authURL)
        let apiKey = await service.fetch()
        try writeGrokSession(expiresAt: "2000-01-01T00:00:00Z", to: authURL)
        let expired = await service.fetch()

        XCTAssertEqual(missing, .failure(.signedOut))
        XCTAssertEqual(apiKey, .failure(.signedOut))
        XCTAssertEqual(expired, .failure(.credentialsExpired))
    }

    func testRejectedRequestsAndEmptyConfigsAreUnavailable() async throws {
        let authURL = try makeAuthURL()
        try writeGrokSession(expiresAt: "2999-01-01T00:00:00Z", to: authURL)
        let rejected = GrokQuotaService(authURL: authURL) { _ in
            try grokBillingReply(#"{"error":"unauthorized"}"#, status: 401)
        }
        let empty = GrokQuotaService(authURL: authURL) { _ in try grokBillingReply(#"{"config":null}"#) }

        let rejectedResult = await rejected.fetch()
        let emptyResult = await empty.fetch()

        XCTAssertEqual(rejectedResult, .failure(.requestFailed))
        XCTAssertEqual(emptyResult, .failure(.emptyLimits))
    }

    @MainActor
    func testModelKeepsTheLastSnapshotOnceTheSessionExpires() async throws {
        let authURL = try makeAuthURL()
        let model = GrokQuotaModel(
            quotaService: GrokQuotaService(authURL: authURL) { _ in
                try grokBillingReply(#"{"config":{"creditUsagePercent":25}}"#)
            }
        )

        try writeGrokSession(expiresAt: "2000-01-01T00:00:00Z", to: authURL)
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .unavailable(.credentialsExpired))

        try writeGrokSession(expiresAt: "2999-01-01T00:00:00Z", to: authURL)
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        let snapshot = GrokQuotaSnapshot(period: nil, window: QuotaWindow(usedPercent: 25, resetsAt: nil))
        XCTAssertEqual(model.state, .available(snapshot, stale: nil))

        try writeGrokSession(expiresAt: "2000-01-01T00:00:00Z", to: authURL)
        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(snapshot, stale: .credentialsExpired))
    }

    @MainActor
    func testRefreshesCoalesceAndRespectCooldown() async throws {
        let authURL = try makeAuthURL()
        try writeGrokSession(expiresAt: nil, to: authURL)
        let requests = Mutex(0)
        let model = GrokQuotaModel(
            quotaService: GrokQuotaService(authURL: authURL) { _ in
                requests.withLock { $0 += 1 }
                return try grokBillingReply(#"{"config":{"creditUsagePercent":25}}"#)
            }
        )

        model.refresh()
        model.refresh()
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(requests.withLock { $0 }, 1)

        model.refresh()
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(requests.withLock { $0 }, 1)
    }

    private func makeAuthURL() throws -> URL {
        try makeTemporaryDirectory().appending(path: "auth.json")
    }
}

func writeGrokSession(expiresAt: String?, to authURL: URL) throws {
    let expiry = expiresAt.map { #","expires_at":"\#($0)""# } ?? ""
    try Data(
        """
        {"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828":{"key":"access-token","auth_mode":"oidc",\
        "create_time":"2026-09-24T13:51:26.374406Z","user_id":"user-1","refresh_token":"refresh"\(expiry)}}
        """.utf8
    )
    .write(to: authURL)
}

func grokBillingReply(_ body: String, status: Int = 200) throws -> (Data, URLResponse) {
    let url = try XCTUnwrap(URL(string: "https://cli-chat-proxy.grok.com/v1/billing"))
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
    return (Data(body.utf8), response)
}
