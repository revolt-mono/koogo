import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var models: AppModels

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let preferences = ProviderPreferences()
        let usageModel = UsageModel(pipeline: UsagePipeline())
        usageModel.refresh(providers: preferences.usageProviders)
        let quotaModel = QuotaModel()
        quotaModel.refresh(preferences.quotaProviders)
        let updateModel = UpdateModel()
        updateModel.start()
        let sampler = ActivitySampler()
        let mouse = MouseModel()
        mouse.start()
        _models = State(
            initialValue: AppModels(
                preferences: preferences,
                usage: usageModel,
                quota: quotaModel,
                codexReset: CodexQuotaResetModel(quota: quotaModel),
                update: updateModel,
                breakReminder: BreakReminderModel(notifications: BreakReminderNotificationCenter()),
                inbox: InboxModel(),
                activity: ActivityModel { try await sampler.sample() },
                mouse: mouse
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .fontDesign(.rounded)
                .environment(models)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .fontDesign(.rounded)
                .environment(models)
        }
        .windowResizability(.contentSize)
    }
}
