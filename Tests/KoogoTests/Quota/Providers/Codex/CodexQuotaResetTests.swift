import Foundation
import XCTest

@testable import Koogo

final class CodexQuotaResetTests: XCTestCase {
    func testFetchKeepsUsableCreditsSoonestFirstAndTheAuthoritativeTotal() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let available = CodexQuotaTestWorkspace.resetCredit
        let credits = """
            [
              {"id":"credit-z","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4000000000,"title":null,"description":null},
              {"id":"credit-b","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4102444800,"title":null,"description":null},
              {"id":"credit-c","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":null,"title":null,"description":null},
              \(available.replacingOccurrences(of: "credit-a", with: "credit-d").replacingOccurrences(of: "available", with: "redeemed")),
              \(available.replacingOccurrences(of: "credit-a", with: "credit-e").replacingOccurrences(of: "codexRateLimits", with: "unknown")),
              \(available)
            ]
            """
        let executable = try workspace.makeAppServer(
            quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 5, credits: credits)
        )
        let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()
        let summary = try XCTUnwrap(snapshot.resetCredits)
        let details = try XCTUnwrap(summary.credits)

        XCTAssertEqual(summary.availableCount, 5)
        XCTAssertEqual(details.map(\.id), ["credit-z", "credit-a", "credit-b", "credit-c"])
        XCTAssertEqual(details[1].title, "Usage reset")
        XCTAssertEqual(details[2].title, "Banked reset")
        XCTAssertEqual(details[1].expiresAt, Date(timeIntervalSince1970: 4_102_444_800))
        XCTAssertFalse(details[1].canUse(at: Date(timeIntervalSince1970: 4_102_444_800)))
        XCTAssertNil(details[3].expiresAt)
        XCTAssertTrue(details[3].canUse(at: .distantFuture))
    }

    func testCountOnlyAndEmptyDetailsRemainDistinct() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        for credits in ["null", "[]"] {
            let executable = try workspace.makeAppServer(
                quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 3, credits: credits)
            )
            let snapshot = try await CodexQuotaSource(executableCandidates: [executable]).load().get()
            let summary = try XCTUnwrap(snapshot.resetCredits)
            XCTAssertEqual(summary.availableCount, 3)
            XCTAssertEqual(summary.credits, credits == "null" ? nil : [])
        }
    }

    func testConsumeSendsCreditIDAndKeyAndDecodesAllOutcomes() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let attempt = resetAttempt()
        let cases: [(String, CodexQuotaResetOutcome)] = [
            ("reset", .reset), ("alreadyRedeemed", .alreadyRedeemed),
            ("nothingToReset", .nothingToReset), ("noCredit", .noCredit),
        ]
        for (value, expected) in cases {
            let executable = try workspace.makeAppServer(
                consumeResponse: "{\"id\":2,\"result\":{\"outcome\":\"\(value)\"}}"
            )
            let result = await CodexQuotaSource(executableCandidates: [executable]).consume(attempt)
            XCTAssertEqual(result, .success(expected))
        }
        let requests = try workspace.lines(in: workspace.consumeRequestsFile)
        XCTAssertEqual(requests.count, 4)
        for line in requests {
            let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertEqual(request["method"] as? String, "account/rateLimitResetCredit/consume")
            let params = try XCTUnwrap(request["params"] as? [String: String])
            XCTAssertEqual(params, ["creditId": "credit-a", "idempotencyKey": attempt.idempotencyKey.uuidString])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.readRequestsFile.path))
    }

    func testRPCErrorsMapToTypedFailuresAndUnknownOutcomesAreNotSuccess() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let attempt = resetAttempt()
        let cases: [(String, ToolFailure)] = [
            ("{\"id\":2,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}", .rpc(code: -32601)),
            ("{\"id\":2,\"error\":{\"code\":-32603,\"message\":\"Timed out\"}}", .rpc(code: -32603)),
            ("{\"id\":2,\"result\":{\"outcome\":\"future-outcome\"}}", .invalidMessage),
        ]
        for (response, expected) in cases {
            let executable = try workspace.makeAppServer(consumeResponse: response)
            let result = await CodexQuotaSource(executableCandidates: [executable]).consume(attempt)
            XCTAssertEqual(result, .failure(.unconfirmed(expected)))
        }
    }

    func testHandshakeFailureCannotSendAConsumeRequest() async throws {
        let root = try makeTemporaryDirectory()
        let unexpected = root.appending(path: "unexpected")
        let executable = try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                IFS= read -r initialize
                printf '%s\\n' '{"id":1,"error":{"code":-32603}}'
                while IFS= read -r request; do
                  printf '%s\\n' "$request" >> '\(unexpected.path)'
                done
                """
        )

        let result = await CodexQuotaSource(executableCandidates: [executable]).consume(resetAttempt())

        XCTAssertEqual(result, .failure(.rejected(.rpc(code: -32603))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpected.path))
    }

    func testTimeoutKeepsTheRequestPhase() async throws {
        let workspace = CodexQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let initializing = try workspace.makeAppServer(onStart: "while :; do :; done")
        let consuming = try workspace.makeAppServer(onConsume: "while :; do :; done")

        let rejected = await CodexQuotaSource(executableCandidates: [initializing], timeout: .milliseconds(500))
            .consume(resetAttempt())
        let unconfirmed = await CodexQuotaSource(executableCandidates: [consuming], timeout: .milliseconds(500))
            .consume(resetAttempt())

        XCTAssertEqual(rejected, .failure(.rejected(.timedOut)))
        XCTAssertEqual(unconfirmed, .failure(.unconfirmed(.timedOut)))
    }

    func testFailureBeforeTheWriteIsRejected() async {
        let result = await CodexQuotaSource(executableCandidates: []).consume(resetAttempt())
        XCTAssertEqual(result, .failure(.rejected(.notFound)))
    }
}

private func resetAttempt() -> CodexQuotaResetAttempt {
    CodexQuotaResetAttempt(
        credit: QuotaSnapshot.ResetCredit(
            id: "credit-a",
            title: "Usage reset",
            expiresAt: Date(timeIntervalSince1970: 4_102_444_800)
        )
    )
}
