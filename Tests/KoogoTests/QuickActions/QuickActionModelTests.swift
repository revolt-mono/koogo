import XCTest

@testable import Koogo

@MainActor
final class QuickActionModelTests: XCTestCase {
  func testScanLeavesTargetsReadyOrIdle() async throws {
    let ready = QuickActionModel(scan: { ["a", "b"] }, perform: { _ in })
    let idle = QuickActionModel<[String]>(scan: { nil }, perform: { _ in })

    XCTAssertEqual(ready.phase, .unscanned)
    ready.refresh()
    idle.refresh()

    try await Poll.until { ready.phase == .ready(["a", "b"]) && idle.phase == .idle }
  }

  func testScanFailureCarriesTheMessageAndActivatingRescans() async throws {
    let scans = Counter()
    let model = QuickActionModel<Int>(
      scan: {
        if scans.increment() == 1 {
          throw TestFailure()
        } else {
          3
        }
      },
      perform: { _ in },
    )

    model.refresh()
    try await Poll.until { model.phase == .scanFailed("test failure") }
    model.activate?()
    try await Poll.until { model.phase == .ready(3) }
  }

  func testPerformRunsTheActionThenRescans() async throws {
    let scans = Counter()
    let performed = Counter()
    let model = QuickActionModel(
      scan: { scans.increment() == 1 ? 7 : nil },
      perform: { targets in
        XCTAssertEqual(targets, 7)
        performed.increment()
      },
    )
    model.refresh()
    try await Poll.until { model.phase == .ready(7) }

    model.perform()

    try await Poll.until { model.phase == .idle }
    XCTAssertEqual(performed.value, 1)
  }

  func testPerformFailureCarriesTheMessageAndRefreshRescans() async throws {
    let model = QuickActionModel(scan: { 1 }, perform: { _ in throw TestFailure() })
    model.refresh()
    try await Poll.until { model.phase == .ready(1) }

    model.perform()
    try await Poll.until { model.phase == .performFailed("test failure") }

    model.refresh()
    try await Poll.until { model.phase == .ready(1) }
  }

  func testRefreshIsIgnoredWhileTheActionRuns() async throws {
    let gate = Gate()
    let model = QuickActionModel(scan: { 1 }, perform: { _ in await gate.wait() })
    model.refresh()
    try await Poll.until { model.phase == .ready(1) }

    model.perform()
    XCTAssertEqual(model.phase, .performing(1))
    model.refresh()
    XCTAssertEqual(model.phase, .performing(1))

    await gate.open()
    try await Poll.until { model.phase == .ready(1) }
  }

  func testPerformIsIgnoredUnlessReady() async throws {
    let performed = Counter()
    let model = QuickActionModel<Int>(scan: { nil }, perform: { _ in performed.increment() })
    model.refresh()
    try await Poll.until { model.phase == .idle }

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
      perform: { _ in },
    )

    model.refresh()
    try await Poll.until { scans.value == 1 }
    model.refresh()
    try await Poll.until { model.phase == .ready(2) }

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
      perform: { _ in },
    )
    let performing = QuickActionModel(scan: { 1 }, perform: { _ in await gate.wait() })
    performing.refresh()
    try await Poll.until { performing.phase == .ready(1) }
    performing.perform()

    scanning.refresh()
    try await Poll.until { scans.value == 1 }
    scanning.cancel()
    performing.cancel()
    await gate.open()

    try await Poll.until { performing.phase == .ready(1) }
    XCTAssertEqual(scanning.phase, .unscanned)
  }

  func testScanlessActionIsReadyBeforeAndAfterPerforming() async throws {
    let performed = Counter()
    let model = QuickActionModel(perform: { performed.increment() })

    XCTAssertTrue(model.phase.isReady)
    model.perform()

    try await Poll.until { model.phase.isReady }
    XCTAssertEqual(performed.value, 1)
  }
}

private struct TestFailure: LocalizedError {
  var errorDescription: String? {
    "test failure"
  }
}

extension QuickActionModel.Phase {
  fileprivate var isReady: Bool {
    if case .ready = self {
      true
    } else {
      false
    }
  }
}

private actor Gate {
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

  private var isOpen = false
  private var waiters = [CheckedContinuation<Void, Never>]()
}
