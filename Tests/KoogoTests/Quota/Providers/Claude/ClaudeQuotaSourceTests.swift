import Foundation
import Testing

@testable import Koogo

struct ClaudeQuotaSourceTests {
  @Test
  func `fetch sends one isolated usage request and reads the plan windows`() async throws {
    let workspace = ClaudeQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeCLI()
    let snapshot = try await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.plan == "Max")
    #expect(snapshot.windows["Session"]?.usedPercent == 12)
    #expect(snapshot.windows["Session"]?.resetsAt == Date(timeIntervalSince1970: 1_788_220_800.125))
    #expect(snapshot.windows["Weekly"]?.usedPercent == 29)
    #expect(snapshot.windows["Weekly"]?.resetsAt == Date(timeIntervalSince1970: 1_788_393_600))
    #expect(snapshot.windows.map(\.title) == ["Session", "Weekly", "Fable"])
    #expect(snapshot.windows["Fable"]?.usedPercent == 63)
    #expect(snapshot.windows["Fable"]?.resetsAt == Date(timeIntervalSince1970: 1_788_307_200))
    let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8)
    #expect(
      arguments.components(separatedBy: "\n")
        == [
          "--setting-sources",
          "",
          "--settings",
          #"{"disableAllHooks":true,"remoteControlAtStartup":false}"#,
          "--strict-mcp-config",
          "--tools",
          "",
          "--no-session-persistence",
          "-p",
          "--input-format",
          "stream-json",
          "--output-format",
          "stream-json",
          "--verbose",
          "",
        ]
    )
    let requests = try JSONSerialization.jsonObjects(inLinesOf: workspace.requestsFile)
    #expect(requests.count == 1)
    let request = requests[0]
    #expect(request["type"] as? String == "control_request")
    #expect(request["request_id"] as? String == "1")
    #expect(request["request"] as? NSDictionary == ["subtype": "get_usage", "skip_behaviors": true])
  }

  @Test
  func `empty limits are distinct from no plan and from invalid or unanswered output`() async throws {
    let workspace = ClaudeQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    for limits in ["null", ClaudeQuotaTestWorkspace.limits] {
      let executable = try workspace.makeCLI(
        output: ClaudeQuotaTestWorkspace.response(rateLimits: limits, available: false)
      )
      let result = await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == .unavailable(.noPlan), "\(limits)")
    }
    for limits in [
      "null",
      "{}",
      #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":null,"model_scoped":[]}"#,
    ] {
      let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
      let result = await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == .unavailable(.emptyLimits), "\(limits)")
    }
    let outputs: [(String, QuotaUnavailability)] = [
      ("not json", .invalidMessage),
      (#"{"type":"system","subtype":"init"}"#, .sessionFailed),
      (
        #"{"type":"control_response","response":{"subtype":"error","request_id":"1","error":"nope"}}"#,
        .invalidMessage,
      ),
      (
        ClaudeQuotaTestWorkspace.response(rateLimits: "null").replacing(
          #""rate_limits_available":true,"#,
          with: "",
        ),
        .invalidMessage,
      ),
      (
        ClaudeQuotaTestWorkspace.response(
          rateLimits: #"{"five_hour":{"utilization":5,"resets_at":"not a date"}}"#
        ),
        .invalidMessage,
      ),
    ]
    for (output, reason) in outputs {
      let executable = try workspace.makeCLI(output: output)
      let result = await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == .unavailable(reason), "\(output)")
    }
    let executable = try workspace.makeCLI(beforeOutput: "exit 1")
    let result = await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
    #expect(result == .unavailable(.sessionFailed))
  }

  @Test
  func `windows clamp percent and unstarted or unnamed windows are skipped`() async throws {
    let workspace = ClaudeQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let limits = """
      {"five_hour":{"utilization":-8,"resets_at":null},"seven_day":{"utilization":130},\
      "model_scoped":[\
      {"display_name":"Other","utilization":3.9,"resets_at":null},\
      {"display_name":" ","utilization":1,"resets_at":null},\
      {"display_name":"Unstarted","utilization":null,"resets_at":null}]}
      """
    let executable = try workspace.makeCLI(output: ClaudeQuotaTestWorkspace.response(rateLimits: limits))
    let snapshot = try await ClaudeQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.windows["Session"]?.usedPercent == 0)
    #expect(snapshot.windows["Session"]?.resetsAt == nil)
    #expect(snapshot.windows["Weekly"]?.usedPercent == 100)
    #expect(snapshot.windows.map(\.title) == ["Session", "Weekly", "Other"])
    #expect(snapshot.windows["Other"]?.usedPercent == 3)
  }

  @Test
  func `fetch reports missing executable`() async throws {
    let root = try scratch.makeTemporaryDirectory()
    let notExecutable = root.appending(path: "claude")
    try Data().write(to: notExecutable)
    let result = await ClaudeQuotaSource(
      tool: CommandLineTool(candidates: [root.appending(path: "missing"), notExecutable])
    )
    .load()
    #expect(result == .unavailable(.binaryNotFound))
  }

  @Test
  func `timeout and cancellation stop cli and descendants`() async throws {
    let workspace = ClaudeQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let parentMarker = workspace.root.appending(path: "parent")
    let childMarker = workspace.root.appending(path: "child")
    for cancel in [false, true] {
      let executable = try workspace.makeCLI(
        beforeOutput: """
          trap '' TERM
          printf '%s' "$$" > '\(parentMarker.path)'
          /bin/sleep 30 &
          printf '%s' "$!" > '\(childMarker.path)'
          wait
          """
      )
      let fetch = Task {
        await ClaudeQuotaSource(
          tool: CommandLineTool(candidates: [executable], timeout: cancel ? .seconds(15) : .seconds(1))
        )
        .load()
      }
      try await Poll.until { FileManager.default.fileExists(atPath: childMarker.path) }
      if cancel {
        fetch.cancel()
      }
      let result = await fetch.value
      #expect(result == .unavailable(cancel ? .sessionFailed : .timedOut))
      for marker in [parentMarker, childMarker] {
        try await Poll.untilExit(pidIn: marker)
        try FileManager.default.removeItem(at: marker)
      }
    }
  }

  private let scratch = Scratch()
}
