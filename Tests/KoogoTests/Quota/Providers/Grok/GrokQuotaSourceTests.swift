import Foundation
import Testing

@testable import Koogo

struct GrokQuotaSourceTests {
  @Test
  func `fetch initializes acp and reads billing without authenticating or creating a session`() async throws {
    let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
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
        """,
    )

    let snapshot = try await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.plan == "SuperGrok Heavy")
    #expect(snapshot.windows.map(\.title) == ["Weekly"])
    #expect(snapshot.windows["Weekly"]?.usedPercent == 3)
    let resetsAt = try #require(snapshot.windows["Weekly"]?.resetsAt)
    #expect(abs(resetsAt.timeIntervalSince1970 - 1_790_533_996.478) < 0.001)
    let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8).split(separator: "\n")
    #expect(arguments == ["--no-auto-update", "agent", "--no-leader", "stdio"])
    let requests = try JSONSerialization.jsonObjects(inLinesOf: workspace.requestsFile)
    #expect(requests.map { $0["method"] as? String } == ["initialize", "_x.ai/billing"])
  }

  @Test
  func `untouched quota is full and monthly periods are kept`() async throws {
    let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAgent(
      billingResponse: GrokQuotaTestWorkspace.response(
        config: #"{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}"#
      )
    )

    let result = await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load()

    try #expect(result.get().windows == [QuotaWindow(title: "Monthly limit", usedPercent: 0, resetsAt: nil)])
  }

  @Test
  func `unknown periods keep the allowance and reset date`() async throws {
    let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAgent(
      billingResponse: GrokQuotaTestWorkspace.response(
        config:
        #"{"creditUsagePercent":120,"currentPeriod":{"type":"future","end":"2026-09-01T08:00:00+08:00"}}"#
      )
    )

    let snapshot = try await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.windows.map(\.title) == ["Usage limit"])
    #expect(snapshot.windows["Usage limit"]?.usedPercent == 100)
    #expect(snapshot.windows["Usage limit"]?.resetsAt == Date(timeIntervalSince1970: 1_788_220_800))
  }

  @Test
  func `missing config is unavailable but an empty config is an untouched allowance`() async throws {
    let untouched = { (plan: String?) in
      QuotaSnapshot(plan: plan, windows: [QuotaWindow(title: "Usage limit", usedPercent: 0, resetsAt: nil)])!
    }
    let cases: [(String, QuotaReading)] = [
      (#"{"id":2,"result":{}}"#, .unavailable(.emptyLimits)),
      (GrokQuotaTestWorkspace.response(config: "null"), .unavailable(.emptyLimits)),
      (GrokQuotaTestWorkspace.response(config: "{}"), .available(untouched("SuperGrok Heavy"))),
      (GrokQuotaTestWorkspace.response(config: "{}", tier: #"" ""#), .available(untouched(nil))),
      (GrokQuotaTestWorkspace.response(config: "{}", tier: "null"), .available(untouched(nil))),
    ]
    for (response, expected) in cases {
      let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
      let executable = try workspace.makeAgent(billingResponse: response)
      let result = await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == expected)
    }
  }

  @Test
  func `a refused billing read means no plan while other errors and unusable fields fail the session`() async throws {
    let refused = #"{"id":2,"error":{"code":-32000,"message":"Authentication required"}}"#
    let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAgent(billingResponse: refused)
    let result = await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
    #expect(result == .unavailable(.noPlan))

    let responses: [(String, QuotaUnavailability)] = [
      (#"{"id":2,"error":{"code":-32603,"message":"Internal error"}}"#, .sessionFailed),
      (GrokQuotaTestWorkspace.response(config: #"{"creditUsagePercent":"invalid"}"#), .invalidMessage),
      (GrokQuotaTestWorkspace.response(config: #"{"currentPeriod":{"end":"invalid"}}"#), .invalidMessage),
    ]
    for (response, reason) in responses {
      let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
      let executable = try workspace.makeAgent(billingResponse: response)
      let result = await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == .unavailable(reason), "\(response)")
    }
  }

  @Test
  func `initialization must succeed before billing`() async throws {
    let responses: [(String, QuotaUnavailability)] = [
      (#"{"id":1,"error":{"code":-32603}}"#, .sessionFailed),
      (#"{"id":1,"error":{"code":-32000,"message":"Authentication refresh failed"}}"#, .sessionFailed),
      (#"{"id":1,"result":{"protocolVersion":2}}"#, .invalidMessage),
      (#"{"id":1,"result":{}}"#, .invalidMessage),
    ]
    for (response, reason) in responses {
      let workspace = GrokQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
      let executable = try workspace.makeAgent(initializeResponse: response)
      let result = await GrokQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == .unavailable(reason), "\(response)")
      try #expect(JSONSerialization.jsonObjects(inLinesOf: workspace.requestsFile).count == 1)
    }
  }

  private let scratch = Scratch()
}
