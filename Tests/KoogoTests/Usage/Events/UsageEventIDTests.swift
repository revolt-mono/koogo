import Testing

@testable import Koogo

struct UsageEventIDTests {
  @Test
  func `ids differ whenever the provider or any logged field differs`() {
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

    #expect(Set(ids).count == ids.count)
    #expect(ids.map(\.provider) == [.claude, .claude, .claude, .claude, .codex, .piAgent, .grok])
    #expect(id(.claude, "ab", "c") == id(.claude, "ab", "c"))
  }
}
