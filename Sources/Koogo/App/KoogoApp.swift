import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var models: AppModels

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let models = AppModels()
        models.usage.refresh(providers: models.preferences.usageProviders)
        models.quota.refresh(models.preferences.quotaProviders)
        models.update.start()
        models.mouse.start()
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
}
