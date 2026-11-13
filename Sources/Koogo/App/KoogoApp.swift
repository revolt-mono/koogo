import AppKit
import SwiftUI

struct KoogoApp: App {
  init() {
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    // appkit's undocumented autofill heuristics spawn a resident system helper on the first text view focus, and
    // koogo's text inputs never autofill.
    UserDefaults.standard.register(defaults: ["NSAutoFillHeuristicsEnabled": false])
    let models = AppModels()
    models.usage.refresh(providers: models.preferences.usageProviders)
    models.quota.refresh(models.preferences.quotaProviders)
    models.update.start()
    models.mouse.start()
    models.keepAwake.start()
    Task { await models.breakReminder.reconcile() }
    _models = State(initialValue: models)
  }

  var body: some Scene {
    MenuBarExtra {
      PanelView()
        .sceneRoot(models)
    } label: {
      Image(systemName: "chart.bar.xaxis")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .sceneRoot(models)
    }
    .windowResizability(.contentSize)
  }

  @State private var models: AppModels
}
