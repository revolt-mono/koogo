import ApplicationServices
import Carbon.HIToolbox
import Darwin
import Synchronization
import Testing

@testable import Koogo

struct ScrollRewriterTests {
  @Test
  func `notches rewrite in place to the step on their own axis`() throws {
    let vertical = try CGEvent.wheel(verticalDelta: 3)
    let horizontal = try CGEvent.wheel(horizontalDelta: -1)

    #expect(rewriter.rewrite(vertical, rules: .defaults, post: unexpectedReplacement) == .deliver)
    #expect(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
    #expect(vertical.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0)
    #expect(vertical.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1) == -3 * 65_536)
    #expect(vertical.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -48)

    #expect(rewriter.rewrite(horizontal, rules: .defaults, post: unexpectedReplacement) == .deliver)
    #expect(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0)
    #expect(horizontal.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3)
    #expect(horizontal.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 48)
  }

  @Test
  func `continuous and phased scrolling passes through untouched`() throws {
    let fields: [CGEventField] = [
      .scrollWheelEventIsContinuous,
      .scrollWheelEventScrollPhase,
      .scrollWheelEventMomentumPhase,
    ]
    for field in fields {
      let event = try CGEvent.wheel(verticalDelta: 1)
      event.setIntegerValueField(field, value: 1)

      #expect(rewriter.rewrite(event, rules: .defaults, post: unexpectedReplacement) == .deliver)
      #expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1)
    }
  }

  @Test
  func `diagonal and zero wheel events drop`() throws {
    for event in [try CGEvent.wheel(verticalDelta: 1, horizontalDelta: 1), try CGEvent.wheel()] {
      #expect(rewriter.rewrite(event, rules: .defaults, post: unexpectedReplacement) == .drop)
    }
  }

  @Test
  func `option precision posts a one line notch between option release and restore`() throws {
    let event = try CGEvent.wheel(verticalDelta: 1)
    event.flags = [.maskAlternate, .maskShift, CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))]
    event.timestamp = 1234
    event.location = CGPoint(x: 40, y: 60)

    var posted = [PostedEvent]()
    #expect(rewriter.rewrite(event, rules: .optionPrecision) { posted.append(PostedEvent($0)) } == .drop)
    #expect(posted.map(\.type) == [.flagsChanged, .scrollWheel, .flagsChanged])
    let released = try #require(posted.first)
    let notch = try #require(posted.dropFirst().first)
    let restored = try #require(posted.last)

    #expect(notch.verticalLines == -1)
    #expect(notch.flags == [.maskShift])
    #expect(notch.timestamp == 1234)
    #expect(notch.location == CGPoint(x: 40, y: 60))
    #expect(released.flags == [.maskShift])
    #expect(released.keyCode == Int64(kVK_RightOption))
    #expect(restored.flags == event.flags)
    #expect(restored.timestamp == 1234)
    #expect(
      event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1,
      "the original is dropped, not edited",
    )
  }

  @Test
  func `horizontal strip keeps its axis and releases left option by default`() throws {
    let event = try CGEvent.wheel(horizontalDelta: 1)
    event.flags = [.maskAlternate]

    var posted = [PostedEvent]()
    #expect(rewriter.rewrite(event, rules: .optionPrecision) { posted.append(PostedEvent($0)) } == .drop)
    #expect(posted.map(\.type) == [.flagsChanged, .scrollWheel, .flagsChanged])
    let notch = try #require(posted.dropFirst().first)

    #expect(notch.verticalLines == 0)
    #expect(notch.horizontalLines == -1)
    #expect(!notch.flags.contains(.maskAlternate))
    #expect(posted.first?.keyCode == Int64(kVK_Option))
    #expect(posted.last?.flags == [.maskAlternate])
  }

  /// macos disables event taps that respond late to system-wide scrolling.
  @Test
  func `rewriting never allocates`() async {
    await #expect(processExitsWith: .success) {
      let rewriter = ScrollRewriter()
      let notch = try CGEvent.wheel(verticalDelta: 1)
      let optionNotch = try CGEvent.wheel(verticalDelta: 1)
      optionNotch.flags = [.maskAlternate]
      let diagonal = try CGEvent.wheel(verticalDelta: 1, horizontalDelta: 1)
      let continuous = try CGEvent.wheel(verticalDelta: 1)
      continuous.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      let atomic = Atomic(InputRules.optionPrecision)
      _ = rewriter.rewrite(optionNotch, rules: .optionPrecision, post: { _ in })

      var remaining = 1_000
      var posted = 0
      // range-based for loops allocate per step in unoptimized builds.
      let count = AllocationCounter.count {
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

      #expect(count == 0)
      #expect(posted == 3_000)
    }
  }

  private let rewriter = ScrollRewriter()

  private func unexpectedReplacement(_: borrowing PostedScrollEvent) {
    Issue.record("unexpected replacement")
  }
}

extension InputRules {
  fileprivate static let defaults = InputRules(MouseSettings(), frontmostApp: nil)

  fileprivate static var optionPrecision: InputRules {
    var rules = defaults
    rules.notchMode = .optionPrecision
    return rules
  }
}

extension CGEvent {
  fileprivate static func wheel(verticalDelta: Int32 = 0, horizontalDelta: Int32 = 0) throws -> CGEvent {
    try #require(
      CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: horizontalDelta == 0 ? 1 : 2,
        wheel1: verticalDelta,
        wheel2: horizontalDelta,
        wheel3: 0,
      )
    )
  }
}

private struct PostedEvent {
  init(_ event: borrowing PostedScrollEvent) {
    type = event.type
    flags = event.flags
    timestamp = event.timestamp
    location = event.location
    verticalLines = event.integerValue(for: .scrollWheelEventDeltaAxis1)
    horizontalLines = event.integerValue(for: .scrollWheelEventDeltaAxis2)
    keyCode = event.integerValue(for: .keyboardEventKeycode)
  }

  let type: CGEventType
  let flags: CGEventFlags
  let timestamp: CGEventTimestamp
  let location: CGPoint
  let verticalLines: Int64
  let horizontalLines: Int64
  let keyCode: Int64
}

/// counts allocations on the calling thread through malloc's logging hook: https://github.com/apple-oss-distributions/libmalloc.
private enum AllocationCounter {
  static func count(_ body: () -> Void) -> Int {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
      preconditionFailure("libmalloc exports malloc_logger")
    }
    let logger = symbol.assumingMemoryBound(to: MallocLogger?.self)
    let previous = logger.pointee
    countedThread = pthread_self()
    allocationCount.store(0, ordering: .relaxed)
    logger.pointee = { type, _, _, _, _, _ in
      guard
        type & AllocationCounter.mallocLogTypeAllocate != 0,
        let countedThread = AllocationCounter.countedThread,
        pthread_equal(pthread_self(), countedThread) != 0
      else {
        return
      }
      AllocationCounter.allocationCount.add(1, ordering: .relaxed)
    }
    body()
    logger.pointee = previous
    return allocationCount.load(ordering: .relaxed)
  }

  private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

  private static let mallocLogTypeAllocate: UInt32 = 2
  private nonisolated(unsafe) static var countedThread: pthread_t?
  private static let allocationCount = Atomic(0)
}
