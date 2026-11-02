import XCTest

@testable import Koogo

final class UsageEventIDTests: XCTestCase {
    func testIdsDifferWheneverAnyLoggedFieldDiffers() {
        let ids: [UsageEventID] = [
            .claude(messageID: "ab".utf8, requestID: "c".utf8),
            .claude(messageID: "a".utf8, requestID: "bc".utf8),
            .claude(messageID: "c".utf8, requestID: "ab".utf8),
            .codex(responseID: "ab".utf8),
            .piAgent(entryID: "ab".utf8),
            .grok(eventID: "ab".utf8, timestampMilliseconds: 1),
        ]

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(
            UsageEventID.claude(messageID: "ab".utf8, requestID: "c".utf8),
            .claude(messageID: "ab".utf8, requestID: "c".utf8)
        )
    }
}
