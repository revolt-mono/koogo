import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaResetTests: XCTestCase {
    private var workspace: CodexQuotaTestWorkspace!

    override func setUpWithError() throws {
        workspace = try CodexQuotaTestWorkspace()
    }

    override func tearDownWithError() throws {
        try workspace.remove()
    }

    func testFetchKeepsUsableCreditsSoonestFirstAndTheAuthoritativeTotal() async throws {
        let available = CodexQuotaTestWorkspace.resetCredit
        let credits = """
            [
              {"id":"credit-b","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4102444800,"title":null,"description":null},
              {"id":"credit-c","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":null,"title":null,"description":null},
              \(available.replacingOccurrences(of: "credit-a", with: "credit-d").replacingOccurrences(of: "available", with: "redeemed")),
              \(available.replacingOccurrences(of: "credit-a", with: "credit-e").replacingOccurrences(of: "codexRateLimits", with: "unknown")),
              \(available)
            ]
            """
        let executable = try workspace.makeResetExecutable(
            quotaResponse: CodexQuotaTestWorkspace.resetQuotaResponse(count: 5, credits: credits)
        )
        let snapshot = try await CodexQuotaService(executableURL: executable).fetch().get()
        let summary = try XCTUnwrap(snapshot.account?.resetCredits)
        let details = try XCTUnwrap(summary.credits)

        XCTAssertEqual(summary.availableCount, 5)
        XCTAssertEqual(details.map(\.id), ["credit-a", "credit-b", "credit-c"])
        XCTAssertEqual(details[0].title, "Usage reset")
        XCTAssertEqual(details[0].expiresAt, Date(timeIntervalSince1970: 4_102_444_800))
        XCTAssertFalse(details[0].canUse(at: Date(timeIntervalSince1970: 4_102_444_800)))
        XCTAssertNil(details[2].expiresAt)
        XCTAssertTrue(details[2].canUse(at: .distantFuture))
    }

    func testCountOnlyAndEmptyDetailsRemainDistinct() async throws {
        for count in [0, 3] {
            for credits in ["null", "[]"] {
                let executable = try workspace.makeResetExecutable(
                    quotaResponse: CodexQuotaTestWorkspace.resetQuotaResponse(count: count, credits: credits)
                )
                let snapshot = try await CodexQuotaService(executableURL: executable).fetch().get()
                let summary = try XCTUnwrap(snapshot.account?.resetCredits)
                XCTAssertEqual(summary.availableCount, UInt64(count))
                XCTAssertEqual(summary.credits, credits == "null" ? nil : [])
            }
        }
    }

    func testConsumeSendsCreditIDAndKeyAndDecodesAllOutcomes() async throws {
        let attempt = CodexQuotaTestWorkspace.resetAttempt()
        let cases: [(String, CodexQuotaResetOutcome)] = [
            ("reset", .reset), ("alreadyRedeemed", .alreadyRedeemed),
            ("nothingToReset", .nothingToReset), ("noCredit", .noCredit),
        ]
        for (value, expected) in cases {
            let executable = try workspace.makeResetExecutable(
                consumeResponse: "{\"id\":2,\"result\":{\"outcome\":\"\(value)\"}}"
            )
            let result = await CodexQuotaService(executableURL: executable).consume(attempt)
            XCTAssertEqual(result, .success(expected))
        }
        let requests = try String(contentsOf: workspace.consumeRequestsFile, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(requests.count, 4)
        for line in requests {
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertEqual(request["method"] as? String, "account/rateLimitResetCredit/consume")
            let params = try XCTUnwrap(request["params"] as? [String: String])
            XCTAssertEqual(params, ["creditId": "credit-a", "idempotencyKey": attempt.idempotencyKey.uuidString])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.readRequestsFile.path))
    }

    func testRPCErrorCodesSurviveAndUnknownOutcomesAreNotSuccess() async throws {
        let attempt = CodexQuotaTestWorkspace.resetAttempt()
        let cases: [(String, CodexQuotaResetFailure)] = [
            ("{\"id\":2,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}", .rpc(code: -32601)),
            ("{\"id\":2,\"error\":{\"code\":-32603,\"message\":\"Timed out\"}}", .rpc(code: -32603)),
            ("{\"id\":2,\"result\":{\"outcome\":\"future-outcome\"}}", .unavailable(.sessionFailed)),
        ]
        for (response, expected) in cases {
            let executable = try workspace.makeResetExecutable(consumeResponse: response)
            let result = await CodexQuotaService(executableURL: executable).consume(attempt)
            XCTAssertEqual(result, .failure(expected))
        }
    }
}
