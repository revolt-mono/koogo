import XCTest

@testable import Koogo

final class UsageEventIDTests: XCTestCase {
    func testIdsDifferWheneverAnyLoggedFieldDiffers() {
        let ids: [UsageEventID] = [
            .claude(messageID: "ab", requestID: "c"),
            .claude(messageID: "a", requestID: "bc"),
            .claude(messageID: "c", requestID: "ab"),
            .codex(turnID: "ab", cumulativeTotal: 1),
            .codex(turnID: "ab", cumulativeTotal: 2),
            .piAgent(entryID: "ab"),
            .grok(eventID: "ab", timestampMilliseconds: 1),
        ]

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(UsageEventID.claude(messageID: "ab", requestID: "c"), .claude(messageID: "ab", requestID: "c"))
    }
}
