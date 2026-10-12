import ApplicationServices
import Darwin
import Synchronization
import XCTest

@testable import Koogo

final class ScrollRewriterTests: XCTestCase {
    private let rewriter = ScrollRewriter()
    private let rules = InputRules(MouseSettings(), frontmostApp: nil)

    func testNotchesRewriteInPlaceToTheStepOnTheirOwnAxis() throws {
        let vertical = try scrollEvent(verticalDelta: 3)
        let horizontal = try scrollEvent(horizontalDelta: -1)
        var lineByLine = rules
        lineByLine.notchMode = .lineByLine
        let inTerminal = try scrollEvent(verticalDelta: 1)

        XCTAssertTrue(rewriter.rewrite(vertical, rules: rules).isDeliver)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1), -3 * 65_536)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -48)

        XCTAssertTrue(rewriter.rewrite(horizontal, rules: rules).isDeliver)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis2), 3)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 48)

        XCTAssertTrue(rewriter.rewrite(inTerminal, rules: lineByLine).isDeliver)
        XCTAssertEqual(inTerminal.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1)
    }

    func testContinuousAndPhasedScrollingPassesThroughUntouched() throws {
        let fields: [CGEventField] = [
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
        ]
        for field in fields {
            let event = try scrollEvent(verticalDelta: 1)
            event.setIntegerValueField(field, value: 1)

            XCTAssertTrue(rewriter.rewrite(event, rules: rules).isDeliver)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        }
    }

    func testDiagonalAndZeroWheelEventsDrop() throws {
        XCTAssertTrue(rewriter.rewrite(try scrollEvent(verticalDelta: 1, horizontalDelta: 1), rules: rules).isDrop)
        XCTAssertTrue(rewriter.rewrite(try scrollEvent(), rules: rules).isDrop)
    }

    func testOptionPrecisionPostsAOneLineNotchBetweenOptionReleaseAndRestore() throws {
        let event = try scrollEvent(verticalDelta: 1)
        event.flags = [.maskAlternate, .maskShift, CGEventFlags(rawValue: 0x40)]
        event.timestamp = 1234
        event.location = CGPoint(x: 40, y: 60)

        let stripped = try XCTUnwrap(rewriter.rewrite(event, rules: precision).stripped)

        XCTAssertEqual(stripped.notch.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1)
        XCTAssertEqual(stripped.notch.flags, [.maskShift])
        XCTAssertEqual(stripped.notch.timestamp, 1234)
        XCTAssertEqual(stripped.notch.location, CGPoint(x: 40, y: 60))
        XCTAssertEqual(stripped.optionReleased.type, .flagsChanged)
        XCTAssertEqual(stripped.optionReleased.flags, [.maskShift])
        XCTAssertEqual(stripped.optionReleased.getIntegerValueField(.keyboardEventKeycode), 0x3D)
        XCTAssertEqual(stripped.optionRestored.type, .flagsChanged)
        XCTAssertEqual(stripped.optionRestored.flags, event.flags)
        XCTAssertEqual(stripped.optionRestored.timestamp, 1234)
        XCTAssertEqual(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            1,
            "the original is dropped, not edited"
        )
    }

    func testHorizontalStripKeepsItsAxisAndReleasesLeftOptionByDefault() throws {
        let event = try scrollEvent(horizontalDelta: 1)
        event.flags = [.maskAlternate]

        let stripped = try XCTUnwrap(rewriter.rewrite(event, rules: precision).stripped)

        XCTAssertEqual(stripped.notch.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(stripped.notch.getIntegerValueField(.scrollWheelEventDeltaAxis2), -1)
        XCTAssertFalse(stripped.notch.flags.contains(.maskAlternate))
        XCTAssertEqual(stripped.optionReleased.getIntegerValueField(.keyboardEventKeycode), 0x3A)
        XCTAssertEqual(stripped.optionRestored.flags, [.maskAlternate])
    }

    /// The tap callback runs inside every scroll on the system; macOS disables a tap that answers late.
    func testRewritingNeverAllocates() throws {
        let notch = try scrollEvent(verticalDelta: 1)
        let optionNotch = try scrollEvent(verticalDelta: 1)
        optionNotch.flags = [.maskAlternate]
        let diagonal = try scrollEvent(verticalDelta: 1, horizontalDelta: 1)
        let continuous = try scrollEvent(verticalDelta: 1)
        continuous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let atomic = Atomic(precision)
        _ = rewriter.rewrite(optionNotch, rules: precision)

        var remaining = 1_000
        // A `for in` over a range allocates per step in unoptimized builds.
        let count = allocations {
            while remaining > 0 {
                remaining -= 1
                let rules = atomic.load(ordering: .relaxed)
                notch.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
                _ = rewriter.rewrite(notch, rules: rules)
                _ = rewriter.rewrite(optionNotch, rules: rules)
                _ = rewriter.rewrite(diagonal, rules: rules)
                _ = rewriter.rewrite(continuous, rules: rules)
            }
        }

        XCTAssertEqual(count, 0)
    }

    private var precision: InputRules {
        var precision = rules
        precision.notchMode = .optionPrecision
        return precision
    }
}

extension ScrollRewrite {
    fileprivate var isDeliver: Bool {
        if case .deliver = self { true } else { false }
    }

    fileprivate var isDrop: Bool {
        if case .drop = self { true } else { false }
    }

    fileprivate var stripped: StrippedNotch? {
        if case .post(let stripped) = self { stripped } else { nil }
    }
}

private func scrollEvent(verticalDelta: Int32 = 0, horizontalDelta: Int32 = 0) throws -> CGEvent {
    let source = CGEventSource(stateID: .hidSystemState)
    source?.pixelsPerLine = 16
    let event = try XCTUnwrap(
        CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: horizontalDelta == 0 ? 1 : 2,
            wheel1: verticalDelta,
            wheel2: horizontalDelta,
            wheel3: 0
        )
    )
    event.setIntegerValueField(.scrollWheelEventScrollCount, value: 1)
    return event
}

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

private let mallocLogTypeAllocate: UInt32 = 2
private nonisolated(unsafe) var countedThread: pthread_t?
private let allocationCount = Atomic(0)

/// Counts heap allocations on the calling thread through `malloc_logger`, the hook malloc stack logging uses. See https://github.com/apple-oss-distributions/libmalloc.
private func allocations(_ body: () -> Void) -> Int {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
        preconditionFailure("libmalloc exports malloc_logger")
    }
    let logger = symbol.assumingMemoryBound(to: MallocLogger?.self)
    let previous = logger.pointee
    countedThread = pthread_self()
    allocationCount.store(0, ordering: .relaxed)
    logger.pointee = { type, _, _, _, _, _ in
        guard type & mallocLogTypeAllocate != 0, let countedThread, pthread_equal(pthread_self(), countedThread) != 0
        else {
            return
        }
        allocationCount.add(1, ordering: .relaxed)
    }
    body()
    logger.pointee = previous
    return allocationCount.load(ordering: .relaxed)
}
