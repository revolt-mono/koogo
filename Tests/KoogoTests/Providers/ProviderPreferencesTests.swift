import Foundation
import Testing

@testable import Koogo

@MainActor
struct ProviderPreferencesTests {
  @Test
  func `defaults show every provider and fetch every quota in declaration order`() throws {
    let preferences = ProviderPreferences(defaults: try scratch.makeIsolatedDefaults())

    #expect(preferences.usageProviders == Provider.allCases)
    #expect(preferences.quotaProviders == [.codex, .claude, .grok])
  }

  @Test
  func `moved provider takes the target slot and orders quota providers too`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let preferences = ProviderPreferences(defaults: defaults)

    preferences.move(.grok, to: .codex)
    #expect(preferences.order == [.grok, .codex, .claude, .piAgent])
    preferences.move(.piAgent, to: .codex)
    #expect(preferences.order == [.grok, .piAgent, .codex, .claude])
    preferences.move(.grok, to: .grok)
    #expect(preferences.quotaProviders == [.grok, .codex, .claude])

    #expect(ProviderPreferences(defaults: defaults).order == [.grok, .piAgent, .codex, .claude])
  }

  @Test
  func `hiding a provider persists and drops its quota`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let preferences = ProviderPreferences(defaults: defaults)

    preferences[isUsageEnabled: .codex] = false

    #expect(preferences.usageProviders == [.claude, .piAgent, .grok])
    #expect(preferences.quotaProviders == [.claude, .grok], "a provider hidden from usage fetches no quota")

    let relaunched = ProviderPreferences(defaults: defaults)
    #expect(relaunched.usageProviders == [.claude, .piAgent, .grok])
    relaunched[isUsageEnabled: .codex] = true
    #expect(ProviderPreferences(defaults: defaults).usageProviders == Provider.allCases)
  }

  @Test
  func `undecodable storage falls back to defaults`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    ProviderPreferences(defaults: defaults)[isUsageEnabled: .codex] = false
    defaults.set(Data("junk".utf8), forKey: "provider-preferences")

    let preferences = ProviderPreferences(defaults: defaults)

    #expect(preferences.order == Provider.allCases)
    #expect(preferences.usageProviders == Provider.allCases)
  }

  @Test
  func `repeated stored providers keep their first slot`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let stored: [String: Any] = ["order": ["grok", "codex", "grok"], "usageDisabled": [String]()]
    defaults.set(
      try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0),
      forKey: "provider-preferences",
    )

    let preferences = ProviderPreferences(defaults: defaults)

    #expect(preferences.order == [.grok, .codex, .claude, .piAgent])
    #expect(preferences.quotaProviders == [.grok, .codex, .claude])
  }

  private let scratch = Scratch()
}
