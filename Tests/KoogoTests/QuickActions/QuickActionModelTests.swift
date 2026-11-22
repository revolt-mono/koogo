import Foundation
import Testing

@testable import Koogo

@MainActor
struct QuickActionModelTests {
  @Test
  func `scan leaves targets ready or empty`() async throws {
    let ready = QuickActionModel(scan: { ["a", "b"] }, perform: { _ in })
    let empty = QuickActionModel<[String]>(scan: { nil }, perform: { _ in })

    #expect(ready.phase == .unscanned)
    ready.refresh()
    empty.refresh()

    try await Poll.until { ready.phase == .ready(["a", "b"]) && empty.phase == .empty }
  }

  @Test
  func `scan failure carries the message and activating rescans`() async throws {
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

  @Test
  func `perform runs the action then rescans`() async throws {
    let scans = Counter()
    let performed = Counter()
    let model = QuickActionModel(
      scan: { scans.increment() == 1 ? 7 : nil },
      perform: { targets in
        #expect(targets == 7)
        performed.increment()
      },
    )
    model.refresh()
    try await Poll.until { model.phase == .ready(7) }

    model.perform()

    try await Poll.until { model.phase == .empty }
    #expect(performed.value == 1)
  }

  @Test
  func `perform failure carries the message and refresh rescans`() async throws {
    let model = QuickActionModel(scan: { 1 }, perform: { _ in throw TestFailure() })
    model.refresh()
    try await Poll.until { model.phase == .ready(1) }

    model.perform()
    try await Poll.until { model.phase == .performFailed("test failure") }

    model.refresh()
    try await Poll.until { model.phase == .ready(1) }
  }

  @Test
  func `refresh is ignored while the action runs`() async throws {
    let gate = Gate()
    let model = QuickActionModel(scan: { 1 }, perform: { _ in await gate.wait() })
    model.refresh()
    try await Poll.until { model.phase == .ready(1) }

    model.perform()
    #expect(model.phase == .performing(1))
    model.refresh()
    #expect(model.phase == .performing(1))

    await gate.open()
    try await Poll.until { model.phase == .ready(1) }
  }

  @Test
  func `perform is ignored unless ready`() async throws {
    let performed = Counter()
    let model = QuickActionModel<Int>(scan: { nil }, perform: { _ in performed.increment() })
    model.refresh()
    try await Poll.until { model.phase == .empty }

    model.perform()

    #expect(model.phase == .empty)
    #expect(performed.value == 0)
  }

  @Test
  func `refresh replaces the scan in flight`() async throws {
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
    #expect(model.phase == .ready(2))
  }

  @Test
  func `cancel drops the scan but not the action`() async throws {
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
    #expect(scanning.phase == .unscanned)
  }

  @Test
  func `scanless action is ready before and after performing`() async throws {
    let performed = Counter()
    let model = QuickActionModel(perform: { performed.increment() })

    #expect(model.phase.isReady)
    model.perform()

    try await Poll.until { model.phase.isReady }
    #expect(performed.value == 1)
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
