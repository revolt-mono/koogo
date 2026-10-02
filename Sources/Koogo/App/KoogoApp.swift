import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var preferences: ProviderPreferences
    @State private var usageModel: UsageModel
    @State private var quotaModel = QuotaModel()
    @State private var updateModel: UpdateModel
    @State private var breakReminderModel = BreakReminderModel(
        notifications: BreakReminderNotificationCenter()
    )
    @State private var inboxModel = InboxModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let preferences = ProviderPreferences()
        let usageModel = UsageModel(pipeline: UsagePipeline())
        usageModel.refresh(providers: preferences.usageProviders)
        _preferences = State(initialValue: preferences)
        _usageModel = State(initialValue: usageModel)
        let updateModel = UpdateModel()
        updateModel.start()
        _updateModel = State(initialValue: updateModel)
    }

    var body: some Scene {
        Group {
            MenuBarExtra {
                PanelView()
                    .fontDesign(.rounded)
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .menuBarExtraStyle(.window)

            Settings {
                SettingsView()
                    .fontDesign(.rounded)
            }
            .windowResizability(.contentSize)
        }
        .environment(preferences)
        .environment(usageModel)
        .environment(quotaModel)
        .environment(updateModel)
        .environment(breakReminderModel)
        .environment(inboxModel)
    }
}
