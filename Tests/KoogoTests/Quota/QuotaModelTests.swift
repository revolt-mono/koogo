import XCTest

@testable import Koogo

@MainActor
final class QuotaModelTests: XCTestCase {
  func testRefreshesCoalesceAndOnlyReloadBypassesTheCooldown() async throws {
    let source = ScriptedQuotaSource([.available(.stub(1)), .available(.stub(2))])
    let model = QuotaModel(sources: .scripted(grok: source))

    model.refresh([.grok])
    model.reload([.grok])
    XCTAssertEqual(model.statuses[.grok], .reading(last: nil))
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))

    model.refresh([.grok])
    XCTAssertFalse(model.statuses[.grok].isBusy)
    XCTAssertEqual(source.loads.withLock { $0 }, 1)

    model.reload([.grok])
    XCTAssertEqual(model.statuses[.grok], .reading(last: .available(.stub(1))))
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(2)))
  }

  func testFailuresKeepTheLastReadingWhileInFlightReplaceASnapshotAndEndTheCooldown() async throws {
    let source = ScriptedQuotaSource([
      .unavailable(.timedOut),
      .available(.stub(1)),
      .unavailable(.sessionFailed),
      .available(.stub(2)),
    ])
    let model = QuotaModel(sources: .scripted(grok: source))

    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.timedOut))

    model.refresh([.grok])
    XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.timedOut))
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))

    model.reload([.grok])
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.sessionFailed))

    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(2)))
  }

  func testCooldownEndsAMinuteAfterAReadingAndADayAfterARefusal() async throws {
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
    XCTAssertFalse(model.statuses[.grok].isBusy)

    now += .milliseconds(1)
    model.refresh([.grok])
    XCTAssertTrue(model.statuses[.grok].isBusy)
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(2)))

    now += .seconds(60)
    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.noPlan))
    now += .seconds(24 * 60 * 60) - .milliseconds(1)
    model.refresh([.grok])
    XCTAssertFalse(model.statuses[.grok].isBusy)

    now += .milliseconds(1)
    model.refresh([.grok])
    try await Poll.until { !model.statuses[.grok].isBusy }
    XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(3)))
    XCTAssertEqual(source.loads.withLock { $0 }, 4)
  }

  func testOnlyTheRequestedProvidersAreRead() async throws {
    let claude = ScriptedQuotaSource([.available(.stub())])
    let grok = ScriptedQuotaSource([])
    let model = QuotaModel(sources: .scripted(claude: claude, grok: grok))

    model.refresh([.claude])
    try await Poll.until { !model.statuses[.claude].isBusy }

    XCTAssertEqual(model.statuses[.claude].latest, .available(.stub()))
    XCTAssertEqual(model.statuses[.grok], .unread)
    XCTAssertEqual(grok.loads.withLock { $0 }, 0)
  }
}
