import Foundation
import XCTest

@testable import Koogo

final class JSONRPCConnectionTests: XCTestCase {
    func testRequestsOwnTheirIDsAndNotificationsHaveNoID() async throws {
        let root = try makeTemporaryDirectory()
        let transcript = root.appending(path: "requests")
        let executable = try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                IFS= read -r request
                printf '%s\\n' "$request" > '\(transcript.path)'
                printf '%s\\n' '{"id":1,"result":{"value":10}}'
                IFS= read -r request
                printf '%s\\n' "$request" >> '\(transcript.path)'
                IFS= read -r request
                printf '%s\\n' "$request" >> '\(transcript.path)'
                printf '%s\\n' '{"method":"progress","params":{}}'
                printf '%s\\n' '{"id":1,"result":"old response"}'
                printf '%s' '{"id":2,"result":{"value":20}}'
                """
        )

        let tool = CommandLineTool(candidates: [executable], timeout: .seconds(3))
        let values = try await tool.session([]) { input, output in
            var connection = JSONRPCConnection(input: input, output: output, dateDecodingStrategy: .iso8601)
            let first: ValueResponse = try connection.request("first")
            try connection.notify("ready")
            let second: ValueResponse = try connection.request("second", params: [String: String]())
            return [first.value, second.value]
        }

        XCTAssertEqual(values, [10, 20])
        let lines = try String(contentsOf: transcript, encoding: .utf8).split(separator: "\n")
        let requests = try lines.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map { $0["method"] as? String }, ["first", "ready", "second"])
        XCTAssertEqual(requests.map { $0["id"] as? Int }, [1, nil, 2])
        XCTAssertNil(requests.first?["params"])
        XCTAssertEqual(requests.last?["params"] as? [String: String], [:])
    }

    func testMalformedOrAmbiguousMessagesCannotBecomeSuccess() async throws {
        let replies = [
            #"{"id":1,"result":{"value":10},"error":{"code":-32603}}"#,
            #"{"id":1}"#,
            #"{"id":1,"result":null}"#,
            #"{"id":1,"error":null}"#,
            #"{"id":1,"result":{"value":"invalid"}}"#,
            #"{"method":"progress","result":{"value":10}}"#,
            #"{"id":7,"method":"readFile","params":{}}"#,
            "invalid json",
        ]
        for reply in replies {
            do {
                try await request(reply: reply)
                XCTFail("invalid message accepted: \(reply)")
            } catch {
                if case ToolFailure.timedOut = error {
                    XCTFail("invalid message should fail immediately")
                }
            }
        }
    }

    func testRPCErrorRetainsItsCode() async throws {
        do {
            try await request(reply: #"{"id":1,"error":{"code":-32601,"message":"Method not found"}}"#)
            XCTFail("rpc error accepted")
        } catch ToolFailure.rpc(let code) {
            XCTAssertEqual(code, -32601)
        }
    }

    func testClosedOutputFailsWithoutWaitingForTimeout() async throws {
        do {
            try await request(reply: nil)
            XCTFail("eof accepted")
        } catch ToolFailure.closed {}
    }

    private func request(reply: String?) async throws {
        let root = try makeTemporaryDirectory()
        let response = root.appending(path: "response")
        try (reply ?? "").write(to: response, atomically: true, encoding: .utf8)
        let executable = try makeTestExecutable(
            in: root,
            script: """
                #!/bin/sh
                IFS= read -r request
                /bin/cat '\(response.path)'
                """
        )
        try await CommandLineTool(candidates: [executable], timeout: .seconds(3)).session([]) { input, output in
            var connection = JSONRPCConnection(input: input, output: output, dateDecodingStrategy: .iso8601)
            let _: ValueResponse = try connection.request("read")
        }
    }
}

private struct ValueResponse: Decodable {
    let value: Int
}
