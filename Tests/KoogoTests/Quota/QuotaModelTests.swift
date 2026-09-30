import XCTest

@testable import Koogo

/// Owns refresh coalescing, the cooldown, failure handling, the provider switches, and write serialization
/// for every provider.
final class QuotaModelTests: XCTestCase {
    @MainActor
    func testRefreshesCoalesceAndOnlyForceBypassesTheCooldown() async throws {
        let source = ScriptedQuotaSource([.success(.stub(1)), .success(.stub(2))])
        let model = QuotaModel(sources: [.codex: source], defaults: try makeIsolatedDefaults())

        model.refresh(.codex)
        model.refresh(.codex, force: true)
        XCTAssertEqual(model.states[.codex], .loading)
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.states[.codex], .available(.stub(1)))

        model.refresh(.codex)
        XCTAssertFalse(model.isBusy(.codex))
        XCTAssertEqual(source.loads.withLock { $0 }, 1)

        model.refresh(.codex, force: true)
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.states[.codex], .available(.stub(2)))
    }

    @MainActor
    func testFailuresKeepTheLastStateWhileInFlightReplaceASnapshotAndEndTheCooldown() async throws {
        let source = ScriptedQuotaSource([
            .failure(.timedOut), .success(.stub(1)), .failure(.sessionFailed), .success(.stub(2)),
        ])
        let model = QuotaModel(sources: [.grok: source], defaults: try makeIsolatedDefaults())

        model.refresh(.grok)
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.states[.grok], .unavailable(.timedOut))

        model.refresh(.grok)
        XCTAssertEqual(model.states[.grok], .unavailable(.timedOut))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.states[.grok], .available(.stub(1)))

        model.refresh(.grok, force: true)
        XCTAssertEqual(model.states[.grok], .available(.stub(1)))
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.states[.grok], .unavailable(.sessionFailed))

        model.refresh(.grok)
        try await waitUntil { !model.isBusy(.grok) }
        XCTAssertEqual(model.states[.grok], .available(.stub(2)))
    }

    @MainActor
    func testProvidersWithoutASourceOrSwitchedOffHaveNoStateAndAreNeverRead() async throws {
        let defaults = try makeIsolatedDefaults()
        let claude = ScriptedQuotaSource([.success(.stub())])
        let model = QuotaModel(sources: [.codex: ScriptedQuotaSource([]), .claude: claude], defaults: defaults)
        XCTAssertEqual(model.providers, [.codex, .claude])
        XCTAssertEqual(Set(model.states.keys), [.codex, .claude])

        model.setEnabled(false, for: .codex)
        model.setEnabled(false, for: .grok)
        model.refresh(.codex, force: true)
        model.refresh(.grok, force: true)
        XCTAssertNil(model.states[.codex])
        XCTAssertFalse(model.isEnabled(.codex))
        XCTAssertFalse(model.isBusy(.codex))
        XCTAssertNil(model.write(to: .grok) {})
        XCTAssertEqual(defaults.stringArray(forKey: "quota-disabled-providers"), ["codex"])

        // The persisted choice survives relaunch; a provider switched back on starts loading again.
        let relaunched = QuotaModel(sources: [.codex: ScriptedQuotaSource([]), .claude: claude], defaults: defaults)
        XCTAssertEqual(Set(relaunched.states.keys), [.claude])
        relaunched.setEnabled(true, for: .codex)
        XCTAssertEqual(relaunched.states[.codex], .loading)
        XCTAssertEqual(defaults.stringArray(forKey: "quota-disabled-providers"), [])
        relaunched.refresh(.claude)
        try await waitUntil { !relaunched.isBusy(.claude) }
        XCTAssertEqual(relaunched.states[.claude], .available(.stub()))
    }

    @MainActor
    func testSwitchingOffDuringAReadDropsItsResult() async throws {
        let source = ScriptedQuotaSource([.success(.stub())])
        let model = QuotaModel(sources: [.codex: source], defaults: try makeIsolatedDefaults())
        model.refresh(.codex)
        model.setEnabled(false, for: .codex)
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertNil(model.states[.codex])
        XCTAssertEqual(source.loads.withLock { $0 }, 1)
    }

    @MainActor
    func testWriteBlocksReadsAndFinishesAfterTheAuthoritativeReread() async throws {
        let source = ScriptedQuotaSource([.success(.stub(1)), .success(.stub(2)), .success(.stub(3))])
        let model = QuotaModel(sources: [.codex: source], defaults: try makeIsolatedDefaults())
        model.refresh(.codex)
        try await waitUntil { !model.isBusy(.codex) }

        let write = try XCTUnwrap(model.write(to: .codex) { "consumed" })
        XCTAssertTrue(model.isBusy(.codex))
        XCTAssertNil(model.write(to: .codex) { "again" })
        model.refresh(.codex, force: true)
        XCTAssertEqual(model.states[.codex], .available(.stub(1)))

        let value = await write.value
        XCTAssertEqual(value, "consumed")
        XCTAssertEqual(model.states[.codex], .available(.stub(2)))
        XCTAssertEqual(source.loads.withLock { $0 }, 2)

        // A read in flight refuses the write, so a pre-write read can never land after the write.
        model.refresh(.codex, force: true)
        XCTAssertNil(model.write(to: .codex) {})
        try await waitUntil { !model.isBusy(.codex) }
        XCTAssertEqual(model.states[.codex], .available(.stub(3)))
    }
}
