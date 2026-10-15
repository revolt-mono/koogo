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

        XCTAssertEqual(rewriter.rewrite(vertical, rules: rules, post: unexpectedReplacement), .deliver)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1), -3 * 65_536)
        XCTAssertEqual(vertical.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -48)

        XCTAssertEqual(rewriter.rewrite(horizontal, rules: rules, post: unexpectedReplacement), .deliver)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis2), 3)
        XCTAssertEqual(horizontal.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 48)

        XCTAssertEqual(rewriter.rewrite(inTerminal, rules: lineByLine, post: unexpectedReplacement), .deliver)
        XCTAssertEqual(inTerminal.getIntegerValueField(.scrollWheelEventDeltaAxis1), -1)
    }

    func testContinuousAndPhasedScrollingPassesThroughUntouched() throws {
        let fields: [CGEventField] = [
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
        ]
        for field in fields {
            let event = try scrollEvent(verticalDelta: 1)
            event.setIntegerValueField(field, value: 1)

            XCTAssertEqual(rewriter.rewrite(event, rules: rules, post: unexpectedReplacement), .deliver)
            XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 1)
        }
    }

    func testDiagonalAndZeroWheelEventsDrop() throws {
        for event in [try scrollEvent(verticalDelta: 1, horizontalDelta: 1), try scrollEvent()] {
            XCTAssertEqual(rewriter.rewrite(event, rules: rules, post: unexpectedReplacement), .drop)
        }
    }

    func testOptionPrecisionPostsAOneLineNotchBetweenOptionReleaseAndRestore() throws {
        let event = try scrollEvent(verticalDelta: 1)
        event.flags = [.maskAlternate, .maskShift, CGEventFlags(rawValue: 0x40)]
        event.timestamp = 1234
        event.location = CGPoint(x: 40, y: 60)

        var posted: [PostedEvent] = []
        XCTAssertEqual(rewriter.rewrite(event, rules: precision) { posted.append(PostedEvent($0)) }, .drop)
        XCTAssertEqual(posted.map(\.type), [.flagsChanged, .scrollWheel, .flagsChanged])
        let released = try XCTUnwrap(posted.first)
        let notch = try XCTUnwrap(posted.dropFirst().first)
        let restored = try XCTUnwrap(posted.last)

        XCTAssertEqual(notch.verticalLines, -1)
        XCTAssertEqual(notch.flags, [.maskShift])
        XCTAssertEqual(notch.timestamp, 1234)
        XCTAssertEqual(notch.location, CGPoint(x: 40, y: 60))
        XCTAssertEqual(released.flags, [.maskShift])
        XCTAssertEqual(released.keyCode, 0x3D)
        XCTAssertEqual(restored.flags, event.flags)
        XCTAssertEqual(restored.timestamp, 1234)
        XCTAssertEqual(
            event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            1,
            "the original is dropped, not edited"
        )
    }

    func testHorizontalStripKeepsItsAxisAndReleasesLeftOptionByDefault() throws {
        let event = try scrollEvent(horizontalDelta: 1)
        event.flags = [.maskAlternate]

        var posted: [PostedEvent] = []
        XCTAssertEqual(rewriter.rewrite(event, rules: precision) { posted.append(PostedEvent($0)) }, .drop)
        XCTAssertEqual(posted.map(\.type), [.flagsChanged, .scrollWheel, .flagsChanged])
        let notch = try XCTUnwrap(posted.dropFirst().first)

        XCTAssertEqual(notch.verticalLines, 0)
        XCTAssertEqual(notch.horizontalLines, -1)
        XCTAssertFalse(notch.flags.contains(.maskAlternate))
        XCTAssertEqual(posted.first?.keyCode, 0x3A)
        XCTAssertEqual(posted.last?.flags, [.maskAlternate])
    }

    /// macos disables event taps that respond late to system-wide scrolling.
    func testRewritingNeverAllocates() throws {
        let notch = try scrollEvent(verticalDelta: 1)
        let optionNotch = try scrollEvent(verticalDelta: 1)
        optionNotch.flags = [.maskAlternate]
        let diagonal = try scrollEvent(verticalDelta: 1, horizontalDelta: 1)
        let continuous = try scrollEvent(verticalDelta: 1)
        continuous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let atomic = Atomic(precision)
        _ = rewriter.rewrite(optionNotch, rules: precision, post: { _ in })

        var remaining = 1_000
        var posted = 0
        // range-based for loops allocate per step in unoptimized builds.
        let count = allocations {
            while remaining > 0 {
                remaining -= 1
                let rules = atomic.load(ordering: .relaxed)
                notch.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
                _ = rewriter.rewrite(notch, rules: rules) { _ in posted += 1 }
                _ = rewriter.rewrite(optionNotch, rules: rules) { _ in posted += 1 }
                _ = rewriter.rewrite(diagonal, rules: rules) { _ in posted += 1 }
                _ = rewriter.rewrite(continuous, rules: rules) { _ in posted += 1 }
            }
        }

        XCTAssertEqual(count, 0)
        XCTAssertEqual(posted, 3_000)
    }

    private var precision: InputRules {
        var precision = rules
        precision.notchMode = .optionPrecision
        return precision
    }
}

private func unexpectedReplacement(_: borrowing PostedScrollEvent) {
    XCTFail("unexpected replacement")
}

private struct PostedEvent {
    let type: CGEventType
    let flags: CGEventFlags
    let timestamp: CGEventTimestamp
    let location: CGPoint
    let verticalLines: Int64
    let horizontalLines: Int64
    let keyCode: Int64

    init(_ event: borrowing PostedScrollEvent) {
        type = event.type
        flags = event.flags
        timestamp = event.timestamp
        location = event.location
        verticalLines = event.integerValue(for: .scrollWheelEventDeltaAxis1)
        horizontalLines = event.integerValue(for: .scrollWheelEventDeltaAxis2)
        keyCode = event.integerValue(for: .keyboardEventKeycode)
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

/// counts allocations on the calling thread through malloc's logging hook: https://github.com/apple-oss-distributions/libmalloc.
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
