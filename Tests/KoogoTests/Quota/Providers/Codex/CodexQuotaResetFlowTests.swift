import Foundation
import Testing

@testable import Koogo

@MainActor
struct CodexQuotaResetFlowTests {
  @Test
  func `confirmation and cancellation never send a consume`() async throws {
    let source = ScriptedQuotaSource([.available(snapshot())])
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)
    model.beginCodexReset(creditID: "credit-a")
    #expect(model.codexReset == .confirming(attempt))
    model.cancelCodexReset()
    model.submitCodexReset()
    #expect(model.codexReset == .idle)
    #expect(source.consumed.withLock { $0 } == [])
  }

  @Test
  func `confirmation for a credit that expires before submit is refused`() async throws {
    var now = Date.distantPast
    let source = ScriptedQuotaSource([.available(snapshot())])
    let model = try await loadModel(source, now: { now })
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)

    now = try #require(attempt.credit.expiresAt)
    model.submitCodexReset()
    #expect(model.codexReset == .idle)
    #expect(source.consumed.withLock { $0 } == [])
  }

  @Test
  func `consume is single flight and forces authoritative refresh inside cooldown`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .available(snapshot(usedPercent: 17, credits: []))],
      consumes: [.success(.reset)],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    model.submitCodexReset()
    model.submitCodexReset()
    model.beginCodexReset(creditID: "credit-a")
    model.reload([.codex])
    #expect(model.codexReset == .submitting)
    try await Poll.until { !model.statuses[.codex].isBusy }

    #expect(model.codexReset == .completed(.reset))
    let shown = try #require(model.statuses[.codex].latest?.snapshot)
    #expect(shown.windows["Session"]?.usedPercent == 17)
    #expect(shown.resetCredits?.availableCount == 0)
    #expect(source.consumed.withLock { $0.count } == 1)
    #expect(source.loads.withLock { $0 } == 2)
  }

  @Test
  func `successful consume and failed refresh remain separate and refresh can recover`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .unavailable(.sessionFailed), .available(snapshot(credits: []))],
      consumes: [.success(.reset)],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }

    #expect(model.codexReset == .completed(.reset))
    #expect(model.statuses[.codex].latest == .unavailable(.sessionFailed))

    model.reload([.codex])
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexResetCredits?.availableCount == 0)
    #expect(model.codexReset == .completed(.reset))
    #expect(source.consumed.withLock { $0.count } == 1)
  }

  @Test
  func `lost response keeps intent across refresh and retries identical request`() async throws {
    let afterConsume = QuotaReading.available(snapshot(credits: []))
    let source = ScriptedQuotaSource(
      [.available(snapshot()), afterConsume, afterConsume, afterConsume],
      consumes: [.failure(.unconfirmed(.closed)), .success(.alreadyRedeemed)],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .unconfirmed(attempt, .closed))
    #expect(model.codexResetCredits?.availableCount == 0)

    model.cancelCodexReset()
    model.beginCodexReset(creditID: "credit-b")
    model.reload([.codex])
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .unconfirmed(attempt, .closed))
    model.beginCodexReset(creditID: "credit-a")
    #expect(model.codexReset == .unconfirmed(attempt, .closed))
    #expect(source.consumed.withLock { $0 } == [attempt])

    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .completed(.alreadyRedeemed))
    #expect(source.consumed.withLock { $0 } == [attempt, attempt])
  }

  @Test
  func `timeout does not automatically retry or discard intent`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .available(snapshot())],
      consumes: [.failure(.unconfirmed(.timedOut))],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .unconfirmed(attempt, .timedOut))
    #expect(source.consumed.withLock { $0.count } == 1)
    #expect(model.codexResetCredits?.availableCount == 1)
  }

  @Test
  func `failure before the write drops the confirmation with its snapshot`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .unavailable(.timedOut), .available(snapshot())],
      consumes: [.failure(.rejected(.timedOut))],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    #expect(model.codexReset.confirmingAttempt != nil)
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.statuses[.codex].latest == .unavailable(.timedOut))
    #expect(model.codexReset == .idle)
    model.beginCodexReset(creditID: "credit-a")
    #expect(model.codexReset == .idle, "a failed reread leaves no credit to choose")

    model.reload([.codex])
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexResetCredits?.availableCount == 1)
    #expect(model.codexReset == .idle, "a read that restores the credit doesn't revive the confirmation")
  }

  @Test
  func `rejected consume keeps the confirmation while its credit survives`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .available(snapshot())],
      consumes: [.failure(.rejected(.rpc(code: -32601)))],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .confirming(attempt, rejection: .rpc(code: -32601)))
    model.beginCodexReset(creditID: "credit-a")
    #expect(model.codexReset == .confirming(attempt, rejection: .rpc(code: -32601)))
  }

  @Test
  func `rejected consume drops confirmation when read removes credit`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .available(snapshot(credits: []))],
      consumes: [.failure(.rejected(.closed))],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }

    #expect(model.codexReset == .idle)
    #expect(model.codexResetCredits?.availableCount == 0)
  }

  @Test
  func `refresh invalidates confirmation when credit disappears`() async throws {
    for credits in [[], nil] as [[QuotaSnapshot.ResetCredit]?] {
      let source = ScriptedQuotaSource(
        [.available(snapshot()), .available(snapshot(credits: credits))]
      )
      let model = try await loadModel(source)
      model.beginCodexReset(creditID: "credit-a")
      model.reload([.codex])
      try await Poll.until { !model.statuses[.codex].isBusy }
      #expect(model.codexReset == .idle)
      model.submitCodexReset()
      #expect(source.consumed.withLock { $0 } == [])
    }
  }

  @Test
  func `pending read must finish before consume can start`() async throws {
    let source = ScriptedQuotaSource(
      [.available(snapshot()), .available(snapshot()), .available(snapshot())],
      consumes: [.success(.reset)],
    )
    let model = try await loadModel(source)
    model.beginCodexReset(creditID: "credit-a")
    let attempt = try #require(model.codexReset.confirmingAttempt)
    model.reload([.codex])
    model.submitCodexReset()
    #expect(model.statuses[.codex].isBusy)
    #expect(model.codexReset == .confirming(attempt))
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(source.consumed.withLock { $0 } == [])
    model.submitCodexReset()
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexReset == .completed(.reset))
    #expect(source.consumed.withLock { $0 } == [attempt])
  }

  private func loadModel(
    _ source: ScriptedQuotaSource,
    now: @escaping @MainActor () -> Date = { .now },
  ) async throws -> QuotaModel {
    let model = QuotaModel(sources: .scripted(codex: source), now: now)
    model.reload([.codex])
    try await Poll.until { !model.statuses[.codex].isBusy }
    #expect(model.codexResetCredits != nil)
    return model
  }

  private func snapshot(
    usedPercent: Int = 25,
    credits: [QuotaSnapshot.ResetCredit]? = [.stub],
  ) -> QuotaSnapshot {
    QuotaSnapshot(
      windows: [QuotaWindow(title: "Session", usedPercent: Double(usedPercent), resetsAt: nil)],
      resetCredits: QuotaSnapshot.ResetCredits(availableCount: UInt64(credits?.count ?? 0), credits: credits),
    )!
  }
}

extension CodexQuotaResetFlow {
  fileprivate var confirmingAttempt: CodexQuotaResetAttempt? {
    guard case .confirming(let attempt, _) = self else {
      return nil
    }
    return attempt
  }
}
