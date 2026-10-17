import XCTest

@testable import Koogo

@MainActor
final class MouseModelTests: XCTestCase {
    func testStartsOffWithInstalledTerminalsAsLineByLineApps() throws {
        let installed: Set = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.apple.Safari"]
        let mouse = MouseModel(defaults: try makeIsolatedDefaults(), isInstalled: installed.contains)

        XCTAssertEqual(mouse.settings.lineByLineApps, ["com.apple.Terminal", "com.mitchellh.ghostty"])
        XCTAssertFalse(mouse.settings.isEnabled)
        XCTAssertEqual(mouse.status, .off)
    }

    func testSettingsPersistAcrossLaunchesIncludingRemovedPresets() throws {
        let defaults = try makeIsolatedDefaults()
        let mouse = MouseModel(defaults: defaults, isInstalled: { _ in true })

        mouse.settings.wheelStep = .slow
        mouse.settings.direction = .natural
        mouse.settings.isLookUpEnabled = false
        mouse.settings.removeLineByLineApp("com.apple.Terminal")
        mouse.settings.addLineByLineApp("com.microsoft.VSCode")

        let relaunched = MouseModel(defaults: defaults, isInstalled: { _ in true })
        XCTAssertEqual(relaunched.settings, mouse.settings)
        XCTAssertFalse(relaunched.settings.lineByLineApps.contains("com.apple.Terminal"))
        XCTAssertEqual(relaunched.settings.lineByLineApps.last, "com.microsoft.VSCode")
    }

    func testAddingAListedAppKeepsOneEntry() {
        var settings = MouseSettings(lineByLineApps: ["com.mitchellh.ghostty"])

        settings.addLineByLineApp("com.mitchellh.ghostty")

        XCTAssertEqual(settings.lineByLineApps, ["com.mitchellh.ghostty"])
    }

    func testEnabledSettingsWaitForAccessibilityBeforeTheFirstRefresh() throws {
        let defaults = try makeIsolatedDefaults()
        var settings = MouseSettings()
        settings.isEnabled = true
        PersistedValue<MouseSettings>(key: "mouse-settings", defaults: defaults).save(settings)

        XCTAssertEqual(MouseModel(defaults: defaults, isInstalled: { _ in false }).status, .needsAccessibility)
    }

    func testUndecodableSettingsFallBackToDefaultsWithInstalledTerminals() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("junk".utf8), forKey: "mouse-settings")

        XCTAssertEqual(
            MouseModel(defaults: defaults, isInstalled: { _ in true }).settings,
            MouseSettings(lineByLineApps: MouseSettings.terminalApps)
        )
    }
}
