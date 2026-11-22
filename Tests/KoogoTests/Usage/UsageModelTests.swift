import Foundation
import Testing

@testable import Koogo

@MainActor
struct UsageModelTests {
  init() throws {
    workspace = try UsageTestWorkspace()
  }

  @Test
  func `queued refresh uses the injected date`() async throws {
    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    var date = UsageFixture.timestamp
    let model = UsageModel(pipeline: workspace.makePipeline()) { date }

    #expect(model.snapshot == nil)
    model.refresh(providers: Provider.allCases)
    date.addTimeInterval(86_400)
    model.refresh(providers: Provider.allCases)

    try await Poll.until { model.snapshot?.todayTokens(.codex) == 0 }
    #expect(model.snapshot?.providers[.codex]?.periods[.last30Days].total.processedTokens == 120)
  }

  @Test
  func `a queued refresh uses its own provider set`() async throws {
    try workspace.write(
      CodexLog.session(input: 100, output: 20),
      to: workspace.codexSessions.appending(path: "session.jsonl"),
    )
    let model = UsageModel(pipeline: workspace.makePipeline(), now: { UsageFixture.timestamp })

    model.refresh(providers: Provider.allCases)
    model.refresh(providers: [.claude, .piAgent, .grok])
    try await Poll.until { model.snapshot != nil && model.snapshot?.providers[.codex] == nil }

    let snapshot = try #require(model.snapshot)
    #expect(Set(snapshot.providers.keys) == [.claude, .piAgent, .grok])
    #expect(snapshot.summary.today.current.processedTokens == 0)
  }

  @Test
  func `refresh skips providers without home until they appear`() async throws {
    let grokHome = workspace.home(of: .grok)
    try FileManager.default.removeItem(at: grokHome)
    let model = UsageModel(pipeline: workspace.makePipeline(), now: { UsageFixture.timestamp })

    model.refresh(providers: Provider.allCases)
    try await Poll.until { model.snapshot != nil }
    #expect(model.snapshot.map { Set($0.providers.keys) } == [.codex, .claude, .piAgent])

    try FileManager.default.createDirectory(at: grokHome, withIntermediateDirectories: true)
    model.refresh(providers: Provider.allCases)
    try await Poll.until { model.snapshot?.providers[.grok] != nil }
    #expect(model.snapshot.map { Set($0.providers.keys) } == Set(Provider.allCases))
  }

  private let workspace: UsageTestWorkspace
}
