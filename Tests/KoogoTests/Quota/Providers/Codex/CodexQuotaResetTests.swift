import Foundation
import Testing

@testable import Koogo

struct CodexQuotaResetTests {
  @Test
  func `fetch keeps usable credits soonest first and the authoritative total`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let available = CodexQuotaTestWorkspace.resetCredit
    let credits = """
      [
        {"id":"credit-z","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4000000000,"title":null,"description":null},
        {"id":"credit-b","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":4102444800,"title":null,"description":null},
        {"id":"credit-c","resetType":"codexRateLimits","status":"available","grantedAt":1700000000,"expiresAt":null,"title":null,"description":null},
        \(available.replacing("credit-a", with: "credit-d").replacing("available", with: "redeemed")),
        \(available.replacing("credit-a", with: "credit-e").replacing("codexRateLimits", with: "unknown")),
        \(available)
      ]
      """
    let executable = try workspace.makeAppServer(
      quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 5, credits: credits)
    )
    let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()
    let summary = try #require(snapshot.resetCredits)
    let details = try #require(summary.credits)

    #expect(summary.availableCount == 5)
    #expect(details.map(\.id) == ["credit-z", "credit-a", "credit-b", "credit-c"])
    #expect(details[1].title == "Usage reset")
    #expect(details[2].title == "Banked reset")
    #expect(details[1].expiresAt == Date(timeIntervalSince1970: 4_102_444_800))
    #expect(!details[1].canUse(at: Date(timeIntervalSince1970: 4_102_444_800)))
    #expect(details[3].expiresAt == nil)
    #expect(details[3].canUse(at: .distantFuture))
  }

  @Test
  func `count only and empty details remain distinct`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    for credits in ["null", "[]"] {
      let executable = try workspace.makeAppServer(
        quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: 3, credits: credits)
      )
      let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()
      let summary = try #require(snapshot.resetCredits)
      #expect(summary.availableCount == 3)
      #expect(summary.credits == (credits == "null" ? nil : []))
    }
  }

  @Test
  func `consume sends credit id and key and decodes all outcomes`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let attempt = resetAttempt()
    let cases: [(String, CodexQuotaResetOutcome)] = [
      ("reset", .reset),
      ("alreadyRedeemed", .alreadyRedeemed),
      ("nothingToReset", .nothingToReset),
      ("noCredit", .noCredit),
    ]
    for (value, expected) in cases {
      let executable = try workspace.makeAppServer(
        consumeResponse: "{\"id\":2,\"result\":{\"outcome\":\"\(value)\"}}"
      )
      let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).consume(attempt)
      #expect(result == .success(expected))
    }
    let requests = try JSONSerialization.jsonObjects(inLinesOf: workspace.requestsFile)
    let consume = "account/rateLimitResetCredit/consume"
    #expect(
      requests.map { $0["method"] as? String }
        == Array(repeating: ["initialize", "initialized", consume], count: 4).flatMap { $0 }
    )
    for request in requests where request["method"] as? String == consume {
      let params = try #require(request["params"] as? [String: String])
      #expect(params == ["creditId": "credit-a", "idempotencyKey": attempt.idempotencyKey.uuidString])
    }
  }

  @Test
  func `refused requests are rejected while failed or unknown outcomes stay unconfirmed`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let attempt = resetAttempt()
    let cases: [(String, CodexAppServer.CallError)] = [
      (#"{"id":2,"error":{"code":-32601,"message":"Method not found"}}"#, .rejected(.rpc(code: -32601))),
      (#"{"id":2,"error":{"code":-32600,"message":"auth required"}}"#, .rejected(.rpc(code: -32600))),
      (#"{"id":2,"error":{"code":-32603,"message":"consume timed out"}}"#, .unconfirmed(.rpc(code: -32603))),
      (#"{"id":2,"result":{"outcome":"future-outcome"}}"#, .unconfirmed(.invalidMessage)),
    ]
    for (response, expected) in cases {
      let executable = try workspace.makeAppServer(consumeResponse: response)
      let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).consume(attempt)
      #expect(result == .failure(expected), "\(response)")
    }
  }

  @Test
  func `handshake failure cannot send a consume request`() async throws {
    let root = try scratch.makeTemporaryDirectory()
    let unexpected = root.appending(path: "unexpected")
    let executable = try TestExecutable.make(
      in: root,
      script: """
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"error":{"code":-32603}}'
        while IFS= read -r request; do
          printf '%s\\n' "$request" >> '\(unexpected.path)'
        done
        """,
    )

    let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).consume(resetAttempt())

    #expect(result == .failure(.rejected(.rpc(code: -32603))))
    #expect(!FileManager.default.fileExists(atPath: unexpected.path))
  }

  @Test
  func `timeout keeps the request phase`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let initializing = try workspace.makeAppServer(onStart: "while :; do :; done")
    let consuming = try workspace.makeAppServer(onConsume: "while :; do :; done")
    // macos vets new executables on first launch, which can exceed the timeout below.
    _ = await CodexQuotaSource(tool: CommandLineTool(candidates: [consuming])).load()

    let rejected = await CodexQuotaSource(
      tool: CommandLineTool(candidates: [initializing], timeout: .milliseconds(500))
    )
    .consume(resetAttempt())
    let unconfirmed = await CodexQuotaSource(
      tool: CommandLineTool(candidates: [consuming], timeout: .milliseconds(500))
    )
    .consume(resetAttempt())

    #expect(rejected == .failure(.rejected(.timedOut)))
    #expect(unconfirmed == .failure(.unconfirmed(.timedOut)))
  }

  @Test
  func `failure before the write is rejected`() async {
    let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [])).consume(resetAttempt())
    #expect(result == .failure(.rejected(.notFound)))
  }

  private let scratch = Scratch()

  private func resetAttempt() -> CodexQuotaResetAttempt {
    CodexQuotaResetAttempt(credit: .stub)
  }
}
