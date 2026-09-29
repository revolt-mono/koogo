import Synchronization
import XCTest

@testable import Koogo

/// Owns refresh coalescing, the cooldown, and stale handling for every provider built on `QuotaModel`.
final class QuotaModelTests: XCTestCase {
    @MainActor
    func testRefreshesCoalesceAndOnlyForceBypassesTheCooldown() async throws {
        let service = ScriptedQuotaService([.success(1), .success(2)])
        let model = QuotaModel(quotaService: service)

        model.refresh()
        model.refresh(force: true)
        XCTAssertEqual(model.state, .loading)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(1, stale: nil))

        model.refresh()
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(service.loads.withLock { $0 }, 1)

        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(2, stale: nil))
    }

    @MainActor
    func testFailuresKeepTheLastStateWhileInFlightAndMarkASnapshotStale() async throws {
        let service = ScriptedQuotaService([.failure(.failed), .success(1), .failure(.failed), .success(2)])
        let model = QuotaModel(quotaService: service)

        model.refresh()
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .unavailable(.failed))

        model.refresh(force: true)
        XCTAssertEqual(model.state, .unavailable(.failed))
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(1, stale: nil))

        model.refresh(force: true)
        XCTAssertEqual(model.state, .available(1, stale: nil))
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(1, stale: .failed))

        model.refresh(force: true)
        try await waitUntil { !model.isRefreshing }
        XCTAssertEqual(model.state, .available(2, stale: nil))
    }
}

private final class ScriptedQuotaService: QuotaService {
    enum Reason: String, Error, Encodable {
        case failed
    }

    static let name = "scripted"

    let loads = Mutex(0)
    private let results: Mutex<[Result<Int, Reason>]>

    init(_ results: [Result<Int, Reason>]) {
        self.results = Mutex(results)
    }

    func load() async -> Result<Int, Reason> {
        loads.withLock { $0 += 1 }
        return results.withLock { $0.removeFirst() }
    }
}
