import Foundation
import Synchronization
import XCTest

@testable import Koogo

@MainActor
final class QuickActionModelTests: XCTestCase {
    func testScanLeavesTargetsReadyOrIdle() async throws {
        let ready = QuickActionModel(scan: { ["a", "b"] }, perform: { _ in })
        let idle = QuickActionModel<[String]>(scan: { nil }, perform: { _ in })

        XCTAssertEqual(ready.phase, .scanning)
        ready.refresh()
        idle.refresh()

        try await waitUntil { ready.phase == .ready(["a", "b"]) && idle.phase == .idle }
    }

    func testScanFailureCarriesTheMessage() async throws {
        let model = QuickActionModel<Int>(scan: { throw TestFailure() }, perform: { _ in })

        model.refresh()

        try await waitUntil { model.phase == .failed("scan broke") }
    }

    func testPerformRunsTheActionThenRescans() async throws {
        let scans = Counter()
        let performed = Counter()
        let model = QuickActionModel(
            scan: { scans.increment() == 1 ? 7 : nil },
            perform: { targets in
                XCTAssertEqual(targets, 7)
                performed.increment()
            }
        )
        model.refresh()
        try await waitUntil { model.phase == .ready(7) }

        model.perform()

        try await waitUntil { model.phase == .idle }
        XCTAssertEqual(performed.value, 1)
    }

    func testPerformFailureCarriesTheMessageAndRefreshRescans() async throws {
        let model = QuickActionModel(scan: { 1 }, perform: { _ in throw TestFailure() })
        model.refresh()
        try await waitUntil { model.phase == .ready(1) }

        model.perform()
        try await waitUntil { model.phase == .failed("scan broke") }

        model.refresh()
        try await waitUntil { model.phase == .ready(1) }
    }

    func testRefreshIsIgnoredWhileTheActionRuns() async throws {
        let gate = Gate()
        let model = QuickActionModel(scan: { 1 }, perform: { _ in await gate.wait() })
        model.refresh()
        try await waitUntil { model.phase == .ready(1) }

        model.perform()
        XCTAssertEqual(model.phase, .performing(1))
        model.refresh()
        XCTAssertEqual(model.phase, .performing(1))

        await gate.open()
        try await waitUntil { model.phase == .ready(1) }
    }

    func testPerformIsIgnoredUnlessReady() async throws {
        let performed = Counter()
        let model = QuickActionModel<Int>(scan: { nil }, perform: { _ in performed.increment() })
        model.refresh()
        try await waitUntil { model.phase == .idle }

        model.perform()

        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(performed.value, 0)
    }

    func testRefreshReplacesTheScanInFlight() async throws {
        let gate = Gate()
        let scans = Counter()
        let model = QuickActionModel(
            scan: {
                if scans.increment() == 1 {
                    await gate.wait()
                    return 1
                }
                return 2
            },
            perform: { _ in }
        )

        model.refresh()
        try await waitUntil { scans.value == 1 }
        model.refresh()
        try await waitUntil { model.phase == .ready(2) }

        await gate.open()

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.phase, .ready(2))
    }

    func testCancelDropsTheScanButNotTheAction() async throws {
        let gate = Gate()
        let scans = Counter()
        let scanning = QuickActionModel(
            scan: {
                scans.increment()
                await gate.wait()
                return 1
            },
            perform: { _ in }
        )
        let performing = QuickActionModel(scan: { 1 }, perform: { _ in await gate.wait() })
        performing.refresh()
        try await waitUntil { performing.phase == .ready(1) }
        performing.perform()

        scanning.refresh()
        try await waitUntil { scans.value == 1 }
        scanning.cancel()
        performing.cancel()
        await gate.open()

        try await waitUntil { performing.phase == .ready(1) }
        XCTAssertEqual(scanning.phase, .scanning)
    }

    func testScanlessActionIsReadyBeforeAndAfterPerforming() async throws {
        let performed = Counter()
        let model = QuickActionModel(perform: { performed.increment() })

        XCTAssertTrue(isReady(model.phase))
        model.perform()

        try await waitUntil { isReady(model.phase) }
        XCTAssertEqual(performed.value, 1)
    }
}

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "scan broke" }
}

private func isReady(_ phase: QuickActionModel<Void>.Phase) -> Bool {
    if case .ready = phase {
        true
    } else {
        false
    }
}

private final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    @discardableResult
    func increment() -> Int {
        count.withLock {
            $0 += 1
            return $0
        }
    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
