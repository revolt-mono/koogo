import Foundation
import Testing

@testable import Koogo

struct DroppedInputTests {
  @Test
  func `unpriced models keep their latest use inside the window`() {
    func time(_ offset: TimeInterval) -> UsageTimestamp {
      UsageTimestamp(UsageFixture.timestamp.addingTimeInterval(offset))
    }
    var dropped = DroppedInput()
    dropped.noteUnpricedModel("old", at: time(-1))
    dropped.noteUnpricedModel("kept", at: time(1))
    dropped.noteUnpricedModel("kept", at: time(0))
    dropped.noteUnpricedModel("aging", at: time(0))
    dropped.noteMalformedLine()

    dropped.discard(before: time(1))

    #expect(Array(dropped.unpricedModels) == ["kept"])
    #expect(dropped.malformedLines == 1)
  }
}
