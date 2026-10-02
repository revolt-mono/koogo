import XCTest

@testable import Koogo

final class QuotaModelTests: XCTestCase {
    @MainActor
    func testRefreshesCoalesceAndOnlyForceBypassesTheCooldown() async throws {
        let source = ScriptedQuotaSource([.available(.stub(1)), .available(.stub(2))])
        let model = makeQuotaModel(grok: source)

        model.refresh([.grok])
        model.refresh([.grok], force: true)
        XCTAssertEqual(model.statuses[.grok], .reading(last: nil))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))

        model.refresh([.grok])
        XCTAssertFalse(model.isBusy(.grok))
        XCTAssertEqual(source.loads.withLock { $0 }, 1)

        model.refresh([.grok], force: true)
        XCTAssertEqual(model.statuses[.grok], .reading(last: .available(.stub(1))))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(2)))
    }

    @MainActor
    func testFailuresKeepTheLastReadingWhileInFlightReplaceASnapshotAndEndTheCooldown() async throws {
        let source = ScriptedQuotaSource([
            .unavailable(.timedOut), .available(.stub(1)), .unavailable(.sessionFailed), .available(.stub(2)),
        ])
        let model = makeQuotaModel(grok: source)

        model.refresh([.grok])
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.timedOut))

        model.refresh([.grok])
        XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.timedOut))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))

        model.refresh([.grok], force: true)
        XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(1)))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .unavailable(.sessionFailed))

        model.refresh([.grok])
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.statuses[.grok].latest, .available(.stub(2)))
    }

    @MainActor
    func testOnlyTheRequestedProvidersAreRead() async throws {
        let claude = ScriptedQuotaSource([.available(.stub())])
        let grok = ScriptedQuotaSource([])
        let model = makeQuotaModel(claude: claude, grok: grok)

        model.refresh([.claude])
        try await waitUntil { !model.isBusy(.claude) }

        XCTAssertEqual(model.statuses[.claude].latest, .available(.stub()))
        XCTAssertEqual(model.statuses[.grok], .unread)
        XCTAssertEqual(grok.loads.withLock { $0 }, 0)
    }
}
