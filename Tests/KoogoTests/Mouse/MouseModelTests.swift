import Foundation
import Testing

@testable import Koogo

@MainActor
struct MouseModelTests {
  @Test
  func `starts off with installed terminals as line by line apps`() throws {
    let installed: Set = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.apple.Safari"]
    let mouse = MouseModel(defaults: try scratch.makeIsolatedDefaults(), isInstalled: installed.contains)

    #expect(mouse.settings.lineByLineApps == ["com.apple.Terminal", "com.mitchellh.ghostty"])
    #expect(!mouse.settings.isEnabled)
  }

  @Test
  func `settings persist across launches including removed presets`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    let mouse = MouseModel(defaults: defaults, isInstalled: { _ in true })

    mouse.settings.wheelStep = .slow
    mouse.settings.direction = .natural
    mouse.settings.isLookUpEnabled = false
    mouse.settings.removeLineByLineApp("com.apple.Terminal")
    mouse.settings.addLineByLineApps(["com.microsoft.VSCode"])

    let relaunched = MouseModel(defaults: defaults, isInstalled: { _ in true })
    #expect(relaunched.settings == mouse.settings)
    #expect(!relaunched.settings.lineByLineApps.contains("com.apple.Terminal"))
    #expect(relaunched.settings.lineByLineApps.last == "com.microsoft.VSCode")
  }

  @Test
  func `undecodable settings fall back to defaults with installed terminals`() throws {
    let defaults = try scratch.makeIsolatedDefaults()
    MouseModel(defaults: defaults, isInstalled: { _ in true }).settings.isLookUpEnabled = false
    defaults.set(Data("junk".utf8), forKey: "mouse-settings")

    #expect(
      MouseModel(defaults: defaults, isInstalled: { _ in true }).settings
        == MouseSettings(lineByLineApps: MouseSettings.terminalApps)
    )
  }

  private let scratch = Scratch()
}
