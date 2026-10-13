import XCTest

@testable import Koogo

@MainActor
final class ProviderPreferencesTests: XCTestCase {
    func testDefaultsShowEveryProviderAndFetchEveryQuotaInDeclarationOrder() throws {
        let preferences = ProviderPreferences(defaults: try makeIsolatedDefaults())

        XCTAssertEqual(preferences.usageProviders, Provider.allCases)
        XCTAssertEqual(preferences.quotaProviders, [.codex, .claude, .grok])
    }

    func testMovedProviderTakesTheTargetSlotAndOrdersQuotaProvidersToo() throws {
        let defaults = try makeIsolatedDefaults()
        let preferences = ProviderPreferences(defaults: defaults)

        preferences.move(.grok, to: .codex)
        XCTAssertEqual(preferences.order, [.grok, .codex, .claude, .piAgent])
        preferences.move(.piAgent, to: .codex)
        XCTAssertEqual(preferences.order, [.grok, .piAgent, .codex, .claude])
        preferences.move(.grok, to: .grok)
        XCTAssertEqual(preferences.quotaProviders, [.grok, .codex, .claude])

        XCTAssertEqual(ProviderPreferences(defaults: defaults).order, [.grok, .piAgent, .codex, .claude])
    }

    func testHidingAProviderPersistsAndDropsItsQuota() throws {
        let defaults = try makeIsolatedDefaults()
        let preferences = ProviderPreferences(defaults: defaults)

        preferences[usage: .codex] = false

        XCTAssertEqual(preferences.usageProviders, [.claude, .piAgent, .grok])
        XCTAssertEqual(preferences.quotaProviders, [.claude, .grok], "a provider hidden from usage fetches no quota")

        let relaunched = ProviderPreferences(defaults: defaults)
        XCTAssertEqual(relaunched.usageProviders, [.claude, .piAgent, .grok])
        XCTAssertEqual(relaunched.quotaProviders, [.claude, .grok])
        relaunched[usage: .codex] = true
        XCTAssertEqual(ProviderPreferences(defaults: defaults).usageProviders, Provider.allCases)
        XCTAssertEqual(ProviderPreferences(defaults: defaults).quotaProviders, [.codex, .claude, .grok])
    }

    func testUndecodableStorageFallsBackToDefaults() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("junk".utf8), forKey: "provider-preferences")

        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertEqual(preferences.order, Provider.allCases)
        XCTAssertEqual(preferences.usageProviders, Provider.allCases)
    }

    func testRepeatedStoredProvidersKeepTheirFirstSlot() throws {
        let defaults = try makeIsolatedDefaults()
        let stored: [String: Any] = ["order": ["grok", "codex", "grok"], "usageDisabled": [String]()]
        defaults.set(
            try PropertyListSerialization.data(fromPropertyList: stored, format: .binary, options: 0),
            forKey: "provider-preferences"
        )

        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertEqual(preferences.order, [.grok, .codex, .claude, .piAgent])
        XCTAssertEqual(preferences.quotaProviders, [.grok, .codex, .claude])
    }
}
