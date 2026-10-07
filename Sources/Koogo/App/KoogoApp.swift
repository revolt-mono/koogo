import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var preferences: ProviderPreferences
    @State private var usageModel: UsageModel
    @State private var quotaModel: QuotaModel
    @State private var codexResetModel: CodexQuotaResetModel
    @State private var updateModel: UpdateModel
    @State private var breakReminderModel = BreakReminderModel(
        notifications: BreakReminderNotificationCenter()
    )
    @State private var inboxModel = InboxModel()
    @State private var activityModel: ActivityModel

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let preferences = ProviderPreferences()
        let usageModel = UsageModel(pipeline: UsagePipeline())
        usageModel.refresh(providers: preferences.usageProviders)
        _preferences = State(initialValue: preferences)
        _usageModel = State(initialValue: usageModel)
        let quotaModel = QuotaModel()
        _quotaModel = State(initialValue: quotaModel)
        _codexResetModel = State(initialValue: CodexQuotaResetModel(quota: quotaModel))
        let updateModel = UpdateModel()
        updateModel.start()
        _updateModel = State(initialValue: updateModel)
        let sampler = ActivitySampler()
        _activityModel = State(initialValue: ActivityModel { try await sampler.sample() })
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
        .environment(codexResetModel)
        .environment(updateModel)
        .environment(breakReminderModel)
        .environment(inboxModel)
        .environment(activityModel)
        .onChange(of: preferences.usageProviders) {
            usageModel.refresh(providers: preferences.usageProviders)
        }
        .onChange(of: preferences.quotaProviders) {
            quotaModel.refresh(preferences.quotaProviders)
        }
    }
}
