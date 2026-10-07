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

    func testSwitchesPersistIndependentlyAndLeaveTheOtherFeatureOn() throws {
        let defaults = try makeIsolatedDefaults()
        let preferences = ProviderPreferences(defaults: defaults)

        preferences.setUsage(false, for: .codex)
        preferences.setQuota(false, for: .grok)

        XCTAssertEqual(preferences.usageProviders, [.claude, .piAgent, .grok])
        XCTAssertEqual(preferences.quotaProviders, [.claude], "a provider hidden from usage fetches no quota")
        XCTAssertTrue(preferences.isQuotaEnabled(.codex))

        let relaunched = ProviderPreferences(defaults: defaults)
        XCTAssertEqual(relaunched.usageProviders, [.claude, .piAgent, .grok])
        XCTAssertEqual(relaunched.quotaProviders, [.claude])
        relaunched.setUsage(true, for: .codex)
        XCTAssertEqual(ProviderPreferences(defaults: defaults).usageProviders, Provider.allCases)
        XCTAssertEqual(ProviderPreferences(defaults: defaults).quotaProviders, [.codex, .claude])
    }

    func testUndecodableStorageFallsBackToDefaults() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("junk".utf8), forKey: "provider-preferences")

        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertEqual(preferences.order, Provider.allCases)
        XCTAssertEqual(preferences.usageProviders, Provider.allCases)
    }
}
