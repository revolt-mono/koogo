import XCTest

@testable import Koogo

final class MouseSettingsTests: XCTestCase {
  func testAddingAppsKeepsOneEntryPerApp() {
    var settings = MouseSettings(lineByLineApps: ["com.mitchellh.ghostty"])

    settings.addLineByLineApps(["com.mitchellh.ghostty", "com.microsoft.VSCode", "com.microsoft.VSCode"])

    XCTAssertEqual(settings.lineByLineApps, ["com.mitchellh.ghostty", "com.microsoft.VSCode"])
  }
}
