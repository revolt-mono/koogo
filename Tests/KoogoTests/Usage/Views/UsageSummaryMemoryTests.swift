import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class UsageSummaryMemoryTests: XCTestCase {
    @MainActor
    func testTextTransitionsKeepFootprintAndRetainedHeapBounded() async throws {
        guard ProcessInfo.processInfo.environment["KOOGO_MEMORY_TESTS"] == "1" else {
            throw XCTSkip("Run separately with KOOGO_MEMORY_TESTS=1 to profile rendered transitions.")
        }
        try XCTSkipIf(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "Numeric transitions require Reduce Motion to be off."
        )

        let host = NSHostingView(rootView: summaryView(step: 0))
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 190),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let heapBefore = allocatedHeapBytes()
        let footprintBefore = physicalFootprint()

        var footprintDuringTransitions: UInt64 = 0
        for step in 1...32 {
            host.rootView = summaryView(step: step)
            try await Task.sleep(for: .milliseconds(100))
            footprintDuringTransitions = max(footprintDuringTransitions, physicalFootprint())
            try await Task.sleep(for: .milliseconds(300))
        }
        // gpu scratch buffers for rasterized transitions count toward the footprint but not the live heap.
        XCTAssertLessThan(footprintDuringTransitions, footprintBefore + 32 * 1_024 * 1_024)
        // reachable font-cache entries evade leak scans.
        XCTAssertLessThan(allocatedHeapBytes(), heapBefore + 16 * 1_024 * 1_024)
    }

    private func physicalFootprint() -> UInt64 {
        guard let usage = LibProc.resourceUsage(of: getpid()) else {
            preconditionFailure("a process can always read its own resource usage")
        }
        return usage.ri_phys_footprint
    }

    private func summaryView(step: Int) -> some View {
        let period = UsageSummaryPeriodSnapshot(
            current: UsagePeriodSnapshot(
                processedTokens: UInt64(12_340_000 + step * 87_321),
                cost: picodollars(Decimal(12_400 + step * 13) / 100)
            ),
            previous: UsagePeriodSnapshot(processedTokens: 0, cost: picodollars(105))
        )
        return UsageSummaryView(summary: UsageSummarySnapshot(today: period, last7Days: period))
            .fontDesign(.rounded)
    }
}
