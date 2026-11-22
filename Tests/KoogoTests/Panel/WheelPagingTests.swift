import AppKit
import Testing

@testable import Koogo

struct WheelPagingTests {
  @Test
  func `wheel clicks step when sideways pass when vertical and drop when tilted`() throws {
    try #expect(WheelPaging(scrollEvent(horizontal: -3)) == .step(1))
    try #expect(WheelPaging(scrollEvent(horizontal: 3)) == .step(-1))
    try #expect(WheelPaging(scrollEvent()) == .pass)
    try #expect(WheelPaging(scrollEvent(vertical: 3)) == .pass)
    try #expect(WheelPaging(scrollEvent(horizontal: 3, vertical: 3)) == .drop)
  }

  @Test
  func `continuous and phased scrolling passes through`() throws {
    try #expect(WheelPaging(scrollEvent(horizontal: -30, phase: .changed)) == .pass)
    try #expect(WheelPaging(scrollEvent(horizontal: -30, units: .pixel)) == .pass)
  }

  private func scrollEvent(
    horizontal: Int32 = 0,
    vertical: Int32 = 0,
    phase: NSEvent.Phase = [],
    units: CGScrollEventUnit = .line,
  ) throws -> NSEvent {
    let event = try #require(
      CGEvent(
        scrollWheelEvent2Source: nil,
        units: units,
        wheelCount: 2,
        wheel1: vertical,
        wheel2: horizontal,
        wheel3: 0,
      )
    )
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
    return try #require(NSEvent(cgEvent: event))
  }
}
