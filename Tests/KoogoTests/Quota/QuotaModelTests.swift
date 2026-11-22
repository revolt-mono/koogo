import Testing

@testable import Koogo

@MainActor
struct QuotaModelTests {
  @Test
  func `refreshes coalesce and only reload bypasses the cooldown`() async throws {
    let source = ScriptedQuotaSource([.available(.stub(1)), .available(.stub(2))])
    let model = QuotaModel(sources: .scripted(grok: source))

    model.refresh([.grok])
    model.reload([.grok])
    #expect(model.statuses[.grok] == .reading(last: nil))
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(1)))

    model.refresh([.grok])
    #expect(!model.statuses[.grok].isBusy)
    #expect(source.loads.withLock { $0 } == 1)

    model.reload([.grok])
    #expect(model.statuses[.grok] == .reading(last: .available(.stub(1))))
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(2)))
  }

  @Test
  func `failures keep the last reading while in flight replace a snapshot and end the cooldown`() async throws {
    let source = ScriptedQuotaSource([
      .unavailable(.timedOut),
      .available(.stub(1)),
      .unavailable(.sessionFailed),
      .available(.stub(2)),
    ])
    let model = QuotaModel(sources: .scripted(grok: source))

    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .unavailable(.timedOut))

    model.refresh([.grok])
    #expect(model.statuses[.grok].latest == .unavailable(.timedOut))
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(1)))

    model.reload([.grok])
    #expect(model.statuses[.grok].latest == .available(.stub(1)))
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .unavailable(.sessionFailed))

    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(2)))
  }

  @Test
  func `cooldown ends a minute after a reading and a day after a refusal`() async throws {
    let source = ScriptedQuotaSource([
      .available(.stub(1)),
      .available(.stub(2)),
      .unavailable(.noPlan),
      .available(.stub(3)),
    ])
    var now = ContinuousClock.now
    let model = QuotaModel(sources: .scripted(grok: source), monotonicNow: { now })

    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    now += .seconds(60) - .milliseconds(1)
    model.refresh([.grok])
    #expect(!model.statuses[.grok].isBusy)

    now += .milliseconds(1)
    model.refresh([.grok])
    #expect(model.statuses[.grok].isBusy)
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(2)))

    now += .seconds(60)
    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .unavailable(.noPlan))
    now += .seconds(24 * 60 * 60) - .milliseconds(1)
    model.refresh([.grok])
    #expect(!model.statuses[.grok].isBusy)

    now += .milliseconds(1)
    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    #expect(model.statuses[.grok].latest == .available(.stub(3)))
    #expect(source.loads.withLock { $0 } == 4)
  }

  @Test
  func `only the requested providers are read`() async throws {
    let claude = ScriptedQuotaSource([.available(.stub())])
    let grok = ScriptedQuotaSource()
    let model = QuotaModel(sources: .scripted(claude: claude, grok: grok))

    model.refresh([.claude])
    try await Poll.until { !model.statuses[.claude].isBusy }

    #expect(model.statuses[.claude].latest == .available(.stub()))
    #expect(model.statuses[.grok] == .unread)
    #expect(grok.loads.withLock { $0 } == 0)
  }
}
