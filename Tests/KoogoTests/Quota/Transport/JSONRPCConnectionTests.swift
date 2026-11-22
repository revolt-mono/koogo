import Foundation
import Testing

@testable import Koogo

struct JSONRPCConnectionTests {
  @Test
  func `requests own their ids and notifications have no id`() async throws {
    let root = try scratch.makeTemporaryDirectory()
    let transcript = root.appending(path: "requests")
    let executable = try TestExecutable.make(
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
        """,
    )

    let tool = CommandLineTool(candidates: [executable], timeout: .seconds(3))
    let values = try await tool.session([]) { streams in
      var connection = JSONRPCConnection(streams, dateDecodingStrategy: .iso8601)
      let first: ValueResponse = try await connection.request("first", params: Never?.none)
      try await connection.notify("ready")
      let second: ValueResponse = try await connection.request("second", params: [String: String]())
      return [first.value, second.value]
    }

    #expect(values == [10, 20])
    let requests = try JSONSerialization.jsonObjects(inLinesOf: transcript)
    #expect(requests.map { $0["method"] as? String } == ["first", "ready", "second"])
    #expect(requests.map { $0["id"] as? Int } == [1, nil, 2])
    #expect(requests.first?["params"] == nil)
    #expect(requests.last?["params"] as? [String: String] == [:])
  }

  @Test
  func `malformed or ambiguous messages cannot become success`() async {
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
      await #expect(throws: ToolFailure.invalidMessage, "\(reply)") { try await request(reply: reply) }
    }
  }

  @Test
  func `rpc error retains its code`() async {
    await #expect(throws: ToolFailure.rpc(code: -32601)) {
      try await request(reply: #"{"id":1,"error":{"code":-32601,"message":"Method not found"}}"#)
    }
  }

  @Test
  func `closed output fails without waiting for timeout`() async {
    await #expect(throws: ToolFailure.closed) { try await request(reply: nil) }
  }

  private let scratch = Scratch()

  private func request(reply: String?) async throws {
    let root = try scratch.makeTemporaryDirectory()
    let response = root.appending(path: "response")
    try (reply ?? "").write(to: response, atomically: true, encoding: .utf8)
    let executable = try TestExecutable.make(
      in: root,
      script: """
        #!/bin/sh
        IFS= read -r request
        /bin/cat '\(response.path)'
        """,
    )
    try await CommandLineTool(candidates: [executable], timeout: .seconds(3)).session([]) { streams in
      var connection = JSONRPCConnection(streams, dateDecodingStrategy: .iso8601)
      let _: ValueResponse = try await connection.request("read", params: Never?.none)
    }
  }
}

private struct ValueResponse: Decodable {
  let value: Int
}
