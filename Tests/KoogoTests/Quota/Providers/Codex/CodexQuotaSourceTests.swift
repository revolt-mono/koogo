import Foundation
import Testing

@testable import Koogo

struct CodexQuotaSourceTests {
  @Test
  func `fetch uses account and named windows and classifies swapped windows`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAppServer(
      quotaResponse: """
        {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":15,"windowDurationMins":10584,"resetsAt":1800000000},"secondary":{"usedPercent":45,"windowDurationMins":285,"resetsAt":1700000000}},"rateLimitsByLimitId":{"codex_bengalfox":{"limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},"codex":{"limitName":null,"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1600000000},"secondary":null}},"rateLimitResetCredits":null}}
        """
    )

    let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(
      snapshot.windows.map(\.title)
        == ["Session", "Weekly", "GPT-5.3-Codex-Spark Session", "GPT-5.3-Codex-Spark Weekly"]
    )
    #expect(snapshot.windows["Session"]?.usedPercent == 45)
    #expect(snapshot.windows["Session"]?.resetsAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(snapshot.windows["Weekly"]?.usedPercent == 15)
    #expect(snapshot.windows["Weekly"]?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(snapshot.windows["GPT-5.3-Codex-Spark Session"]?.usedPercent == 10)
    #expect(snapshot.windows["GPT-5.3-Codex-Spark Weekly"]?.usedPercent == 20)
    #expect(snapshot.plan == nil)
    let arguments = try String(contentsOf: workspace.argumentsFile, encoding: .utf8).split(separator: "\n")
    #expect(arguments == ["app-server", "--stdio"])
    let requests = try JSONSerialization.jsonObjects(inLinesOf: workspace.requestsFile)
    #expect(requests.map { $0["method"] as? String } == ["initialize", "initialized", "account/rateLimits/read"])
  }

  @Test
  func `plan names follow the codex tui and other codes show capitalized`() throws {
    for (planType, expected) in [("team", "Business"), ("mystery", "Mystery")] {
      let snapshot = try decodeSnapshot(
        #"{"rateLimits":{"planType":"\#(planType)","primary":{"usedPercent":25,"windowDurationMins":300}}}"#
      )
      #expect(snapshot.plan == expected, "\(planType)")
    }
  }

  @Test
  func `fetch drops empty ids and titles unnamed windows by id`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let window = #"{"usedPercent":10,"windowDurationMins":300}"#
    let executable = try workspace.makeAppServer(
      quotaResponse: """
        {"id":2,"result":{"rateLimits":{"limitId":"codex"},"rateLimitsByLimitId":{"":{"limitName":"Nameless","primary":\(window)},"id_x":{"limitName":"","primary":\(window)},"id_y":{"limitName":null,"primary":\(window)}}}}
        """
    )

    let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.windows.map(\.title) == ["id_x", "id_y"])
  }

  @Test
  func `fetch omits unknown windows and preserves known zero resets`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAppServer(
      quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(
        usedPercent: 20,
        windowMinutes: 1_440,
        resetCount: 0,
        credits: "[]",
      )
    )

    let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.windows == [])
    #expect(snapshot.plan == "Pro 100")
    #expect(snapshot.resetCredits?.availableCount == 0)
    #expect(snapshot.resetCredits?.credits == [])
  }

  @Test
  func `fetch keeps limits when reset credits are invalid`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAppServer(
      quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(resetCount: -1, credits: "[]")
    )

    let snapshot = try await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load().get()

    #expect(snapshot.windows["Session"]?.usedPercent == 25)
    #expect(snapshot.resetCredits == nil)
  }

  @Test
  func `credits availability and hidden balance`() throws {
    let cases: [(String, QuotaSnapshot.Credits?)] = [
      (#"{"hasCredits":true,"unlimited":false,"balance":" 42.25 "}"#, .balance(amount: 42.25)),
      (#"{"hasCredits":true,"unlimited":false,"balance":"0"}"#, .balance(amount: 0)),
      (#"{"hasCredits":true,"unlimited":false,"balance":null}"#, .available),
      (#"{"hasCredits":true,"unlimited":false,"balance":"unavailable"}"#, .available),
      (#"{"hasCredits":true,"unlimited":false,"balance":"nan"}"#, .available),
      (#"{"hasCredits":false,"unlimited":true,"balance":"12"}"#, .unlimited),
      (#"{"hasCredits":false,"unlimited":false,"balance":"12"}"#, nil),
      ("null", nil),
    ]
    for (credits, expected) in cases {
      let snapshot = try decodeSnapshot(
        #"{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300},"credits":\#(credits)}}"#
      )

      #expect(snapshot.credits == expected, "\(credits)")
      #expect(snapshot.windows["Session"]?.usedPercent == 25)
    }
  }

  @Test
  func `credits without windows or banked resets`() throws {
    let snapshot = try decodeSnapshot(
      #"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":false,"balance":"50"}}}"#
    )

    #expect(snapshot.credits == .balance(amount: 50))
    #expect(snapshot.windows == [])
    #expect(snapshot.resetCredits == nil)
  }

  @Test
  func `fetch reports empty limits when no window or credit survives`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try workspace.makeAppServer(
      quotaResponse: CodexQuotaTestWorkspace.rateLimitsResponse(usedPercent: 20, windowMinutes: 1_440)
    )

    let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load()

    #expect(result == .unavailable(.emptyLimits))
  }

  @Test
  func `a refused read means no plan while other errors fail the session`() async throws {
    let cases: [(Int, QuotaReading)] = [(-32600, .unavailable(.noPlan)), (-32603, .unavailable(.sessionFailed))]
    for (code, expected) in cases {
      let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
      let executable = try workspace.makeAppServer(
        quotaResponse: #"{"id":2,"error":{"code":\#(code),"message":"chatgpt authentication required"}}"#
      )
      let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
      #expect(result == expected, "\(code)")
    }
  }

  @Test
  func `a refused handshake fails the session`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try TestExecutable.make(
      in: workspace.root,
      script: "#!/bin/sh\nIFS= read -r initialize\nprintf '%s\\n' '{\"id\":1,\"error\":{\"code\":-32600}}'\n",
    )

    let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load()

    #expect(result == .unavailable(.sessionFailed))
  }

  @Test
  func `fetch hides quota when launcher closes input before handshake`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let executable = try TestExecutable.make(
      in: workspace.root,
      script:
      "#!/bin/sh\nIFS= read -r initialize\nexec 0<&-\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nsleep 1\n",
    )

    let result = await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load()

    #expect(result == .unavailable(.sessionFailed))
  }

  @Test
  func `cancellation kills descendants spawned during termination grace`() async throws {
    let workspace = CodexQuotaTestWorkspace(root: try scratch.makeTemporaryDirectory())
    let readyMarker = workspace.root.appending(path: "ready")
    let childMarker = workspace.root.appending(path: "child")
    let executable = try TestExecutable.make(
      in: workspace.root,
      script: """
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r rate_limits
        terminate() {
          (trap '' TERM; sleep 5) &
          printf '%s\\n' "$!" > '\(childMarker.path)'
          exit 0
        }
        trap terminate TERM
        printf 'ready\\n' > '\(readyMarker.path)'
        while :; do :; done
        """,
    )

    let fetch = Task {
      await CodexQuotaSource(tool: CommandLineTool(candidates: [executable])).load()
    }
    try await Poll.until(timeout: .seconds(2)) { FileManager.default.fileExists(atPath: readyMarker.path) }

    let cancellationStarted = ContinuousClock.now
    fetch.cancel()
    let result = await fetch.value

    #expect(throws: (any Error).self) { try result.get() }
    #expect(ContinuousClock.now - cancellationStarted < .seconds(3))
    try await Poll.untilExit(pidIn: childMarker)
  }

  private let scratch = Scratch()

  private func decodeSnapshot(_ result: String) throws -> QuotaSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try #require(decoder.decode(CodexQuotaResponse.self, from: Data(result.utf8)).snapshot)
  }
}
