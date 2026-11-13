import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class UsageSummaryMemoryTests: XCTestCase {
  @MainActor
  func testTextTransitionsKeepFootprintAndRetainedHeapBounded() async throws {
    try MemoryMeasurement.skipUnlessRequested()
    try XCTSkipIf(
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      "Numeric transitions require Reduce Motion to be off.",
    )

    let host = NSHostingView(rootView: summaryView(step: 0))
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 320, height: 190),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .seconds(1))
    let heapBefore = MemoryMeasurement.allocatedHeapBytes()
    let footprintBefore = try physicalFootprint()

    var footprintDuringTransitions: UInt64 = 0
    for step in 1...32 {
      host.rootView = summaryView(step: step)
      try await Task.sleep(for: .milliseconds(100))
      footprintDuringTransitions = max(footprintDuringTransitions, try physicalFootprint())
      try await Task.sleep(for: .milliseconds(300))
    }
    // gpu scratch buffers for rasterized transitions count toward the footprint but not the live heap.
    XCTAssertLessThan(footprintDuringTransitions, footprintBefore + 32 * 1_024 * 1_024)
    // reachable font-cache entries evade leak scans.
    XCTAssertLessThan(MemoryMeasurement.allocatedHeapBytes(), heapBefore + 16 * 1_024 * 1_024)
  }

  private func physicalFootprint() throws -> UInt64 {
    try XCTUnwrap(LibProc.resourceUsage(of: getpid())).ri_phys_footprint
  }

  private func summaryView(step: Int) -> some View {
    let period = UsageSummaryPeriodSnapshot(
      current: UsagePeriodSnapshot(
        processedTokens: UInt64(12_340_000 + step * 87_321),
        cost: Picodollars(usd: Decimal(12_400 + step * 13) / 100),
      ),
      previous: UsagePeriodSnapshot(processedTokens: 0, cost: Picodollars(usd: 105)),
    )
    return UsageSummaryView(summary: UsageSummarySnapshot(today: period, last7Days: period))
      .fontDesign(.rounded)
  }
}
