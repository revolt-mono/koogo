import XCTest

@testable import Koogo

final class DroppedInputTests: XCTestCase {
  func testUnpricedModelsKeepTheirLatestUseInsideTheWindow() {
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

    XCTAssertEqual(Array(dropped.unpricedModels), ["kept"])
    XCTAssertEqual(dropped.malformedLines, 1)
  }
}
