import XCTest

@testable import Koogo

final class UsageEventIDTests: XCTestCase {
  func testIdsDifferWheneverTheProviderOrAnyLoggedFieldDiffers() {
    func id(_ provider: Provider, _ fields: String...) -> UsageEventID {
      UsageEventID(provider) { hasher in
        for field in fields {
          hasher.combine(text: field.utf8)
        }
      }
    }
    let ids = [
      id(.claude, "ab", "c"),
      id(.claude, "a", "bc"),
      id(.claude, "c", "ab"),
      id(.claude, "abc"),
      id(.codex, "ab", "c"),
      id(.piAgent, "ab", "c"),
      id(.grok, "ab", "c"),
    ]

    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertEqual(ids.map(\.provider), [.claude, .claude, .claude, .claude, .codex, .piAgent, .grok])
    XCTAssertEqual(id(.claude, "ab", "c"), id(.claude, "ab", "c"))
  }
}
