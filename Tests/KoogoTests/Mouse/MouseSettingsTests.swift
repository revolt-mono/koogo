import Testing

@testable import Koogo

struct MouseSettingsTests {
  @Test
  func `adding apps keeps one entry per app`() {
    var settings = MouseSettings(lineByLineApps: ["com.mitchellh.ghostty"])

    settings.addLineByLineApps(["com.mitchellh.ghostty", "com.microsoft.VSCode", "com.microsoft.VSCode"])

    #expect(settings.lineByLineApps == ["com.mitchellh.ghostty", "com.microsoft.VSCode"])
  }
}
