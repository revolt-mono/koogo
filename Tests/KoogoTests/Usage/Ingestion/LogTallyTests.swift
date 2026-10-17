import Foundation
import XCTest

@testable import Koogo

final class LogTallyTests: XCTestCase {
    func testTallyKeepsTheLatestUnpricedTimestampInsideTheWindow() {
        let windowStart = usageTestTimestamp
        var tally = LogTally()
        tally.noteUnpricedModel("old", at: windowStart - 1)
        tally.noteUnpricedModel("kept", at: windowStart + 1)
        tally.noteUnpricedModel("kept", at: windowStart)
        tally.noteUnpricedModel("aging", at: windowStart)
        tally.noteMalformedLine()

        tally.discard(before: windowStart + 1)

        XCTAssertEqual(Array(tally.unpricedModelIDs), ["kept"])
        XCTAssertEqual(tally.malformedLines, 1)
    }
}
