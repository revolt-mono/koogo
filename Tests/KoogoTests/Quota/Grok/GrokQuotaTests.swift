import Foundation
import XCTest

@testable import Koogo

final class GrokQuotaTests: XCTestCase {
    func testFetchInitializesACPAndReadsBillingWithoutAuthenticatingOrCreatingASession() async throws {
        let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAgent(
            billingResponse: GrokQuotaTestWorkspace.response(
                config: """
                    {"creditUsagePercent":3.9,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
                    "start":"2026-09-20T18:33:16.478027+00:00","end":"2026-09-27T18:33:16.478027+00:00"},\
                    "prepaidBalance":{},"isUnifiedBillingUser":true}
                    """
            ),
            beforeBilling: """
                printf '%s\\n' '{"jsonrpc":"2.0","method":"_x.ai/models/update","params":{}}'
                printf '%s\\n' '{"jsonrpc":"2.0","id":99,"result":"unrelated"}'
                """
        )

        let snapshot = try await GrokQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.account.map(\.title), ["Weekly"])
        XCTAssertEqual(snapshot.account["Weekly"]?.usedPercent, 3)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.account["Weekly"]?.resetsAt).timeIntervalSince1970,
            1_790_533_996.478,
            accuracy: 0.001
        )
        let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(arguments, ["--no-auto-update", "agent", "--no-leader", "stdio"])
        let directory = try String(contentsOf: workspace.directoryFile, encoding: .utf8).trimmingCharacters(
            in: .newlines
        )
        XCTAssertEqual(
            URL(filePath: directory).resolvingSymlinksInPath(),
            URL(filePath: "/tmp").resolvingSymlinksInPath()
        )
        let lines = try String(contentsOf: workspace.requestsFile, encoding: .utf8).split(separator: "\n")
        let requests = try lines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0["method"] as? String }, ["initialize", "_x.ai/billing"])
        XCTAssertEqual(requests.map { $0["id"] as? Int }, [1, 2])
        XCTAssertEqual(requests.map { $0["jsonrpc"] as? String }, ["2.0", "2.0"])
        let initialize = try XCTUnwrap(requests.first?["params"] as? [String: Any])
        XCTAssertEqual(initialize["protocolVersion"] as? Int, 1)
        XCTAssertEqual(initialize["clientCapabilities"] as? [String: String], [:])
        XCTAssertEqual(initialize["clientInfo"] as? [String: String], ["name": "koogo", "version": "1.0"])
        XCTAssertEqual(requests.last?["params"] as? [String: String], [:])
    }

    func testUntouchedQuotaIsFullAndMonthlyPeriodsAreKept() async throws {
        let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAgent(
            billingResponse: GrokQuotaTestWorkspace.response(
                config: #"{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}"#
            )
        )

        let result = await GrokQuotaSource(executableCandidates: [executable]).load()

        XCTAssertEqual(try result.get().account, [QuotaWindow(title: "Monthly limit", usedPercent: 0, resetsAt: nil)])
    }

    func testUnknownPeriodsKeepTheAllowanceAndResetDate() async throws {
        let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
        let executable = try workspace.makeAgent(
            billingResponse: GrokQuotaTestWorkspace.response(
                config:
                    #"{"creditUsagePercent":120,"currentPeriod":{"type":"future","end":"2026-09-01T08:00:00+08:00"}}"#
            )
        )

        let snapshot = try await GrokQuotaSource(executableCandidates: [executable]).load().get()

        XCTAssertEqual(snapshot.account.map(\.title), ["Usage limit"])
        XCTAssertEqual(snapshot.account["Usage limit"]?.usedPercent, 100)
        XCTAssertEqual(snapshot.account["Usage limit"]?.resetsAt, Date(timeIntervalSince1970: 1_788_220_800))
    }

    func testMissingConfigIsUnavailableButAnEmptyConfigIsAnUntouchedAllowance() async throws {
        let untouched = QuotaSnapshot(account: [QuotaWindow(title: "Usage limit", usedPercent: 0, resetsAt: nil)])
        let cases: [(String, Result<QuotaSnapshot?, QuotaUnavailability>)] = [
            (#"{"id":2,"result":{}}"#, .failure(.emptyLimits)),
            (GrokQuotaTestWorkspace.response(config: "null"), .failure(.emptyLimits)),
            (GrokQuotaTestWorkspace.response(config: "{}"), .success(untouched)),
        ]
        for (response, expected) in cases {
            let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
            let executable = try workspace.makeAgent(billingResponse: response)
            let result = await GrokQuotaSource(executableCandidates: [executable]).load()
            XCTAssertEqual(result.map(Optional.some), expected)
        }
    }

    func testBillingErrorsAndUnusableFieldsFailTheSession() async throws {
        let responses = [
            #"{"id":2,"error":{"code":-32000,"message":"Authentication required"}}"#,
            #"{"id":2,"error":{"code":-32603,"message":"HTTP 401"}}"#,
            #"{"id":2,"error":{"code":-32601,"message":"Method not found"}}"#,
            GrokQuotaTestWorkspace.response(config: #"{"creditUsagePercent":"invalid"}"#),
            GrokQuotaTestWorkspace.response(config: #"{"currentPeriod":{"end":"invalid"}}"#),
        ]
        for response in responses {
            let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
            let executable = try workspace.makeAgent(billingResponse: response)
            let result = await GrokQuotaSource(executableCandidates: [executable]).load()
            XCTAssertEqual(result, .failure(.sessionFailed))
        }
    }

    func testInitializationMustSucceedBeforeBilling() async throws {
        let responses = [
            #"{"id":1,"error":{"code":-32603}}"#,
            #"{"id":1,"result":{"protocolVersion":2}}"#,
            #"{"id":1,"result":{}}"#,
        ]
        for response in responses {
            let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
            let executable = try workspace.makeAgent(initializeResponse: response)
            let result = await GrokQuotaSource(executableCandidates: [executable]).load()
            XCTAssertEqual(result, .failure(.sessionFailed))
            let requests = try String(contentsOf: workspace.requestsFile, encoding: .utf8).split(separator: "\n")
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMissingBinaryIsUnavailable() async {
        let result = await GrokQuotaSource(executableCandidates: []).load()
        XCTAssertEqual(result, .failure(.binaryNotFound))
    }

    func testTimeoutCoversInitializationAndBillingAndStopsTheAgent() async throws {
        for stallsDuringInitialize in [true, false] {
            let workspace = GrokQuotaTestWorkspace(root: try makeTemporaryDirectory())
            let executable = try workspace.makeAgent(
                beforeInitialize: stallsDuringInitialize ? "while :; do :; done" : "",
                beforeBilling: stallsDuringInitialize ? "" : "while :; do :; done"
            )
            let result = await GrokQuotaSource(executableCandidates: [executable], timeout: .milliseconds(500)).load()
            XCTAssertEqual(result, .failure(.timedOut))
            let text = try String(contentsOf: workspace.pidFile, encoding: .utf8).trimmingCharacters(in: .newlines)
            let pid = try XCTUnwrap(pid_t(text))
            try await waitUntil(timeout: .seconds(3)) { kill(pid, 0) == -1 && errno == ESRCH }
        }
    }
}
