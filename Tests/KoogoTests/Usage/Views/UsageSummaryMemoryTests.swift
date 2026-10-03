import AppKit
import SwiftUI
import XCTest

@testable import Koogo

final class UsageSummaryMemoryTests: XCTestCase {
    @MainActor
    func testNumericTransitionsKeepRetainedHeapBounded() async throws {
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
        let before = allocatedHeapBytes()

        for step in 1...32 {
            host.rootView = summaryView(step: step)
            try await Task.sleep(for: .milliseconds(400))
        }
        // Font-cache entries are reachable, so a leaks scan misses this growth. Count live
        // heap allocations instead of GPU scratch buffers, which are reclaimed after idle.
        XCTAssertLessThan(allocatedHeapBytes(), before + 16 * 1_024 * 1_024)
    }

    private func summaryView(step: Int) -> some View {
        let period = UsageSummaryPeriodSnapshot(
            current: UsagePeriodSnapshot(
                processedTokens: UInt64(12_340_000 + step * 87_321),
                costUSD: Decimal(12_400 + step * 13) / 100
            ),
            previous: UsagePeriodSnapshot(processedTokens: 0, costUSD: 105)
        )
        return UsageSummaryView(summary: UsageSummarySnapshot(today: period, last30Days: period))
            .fontDesign(.rounded)
    }
}
