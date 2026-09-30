import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var usageModel: UsageModel
    @State private var quotaModel: QuotaModel
    @State private var codexQuotaResetModel: CodexQuotaResetModel
    @State private var updateModel: UpdateModel
    @State private var breakReminderModel = BreakReminderModel(
        notifications: BreakReminderNotificationCenter()
    )
    @State private var inboxModel = InboxModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let usageModel = UsageModel(usageService: UsageService())
        usageModel.refresh()
        _usageModel = State(initialValue: usageModel)
        let quotaModel = QuotaModel()
        _quotaModel = State(initialValue: quotaModel)
        _codexQuotaResetModel = State(
            initialValue: CodexQuotaResetModel(quotaModel: quotaModel, source: CodexQuotaSource())
        )
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
        .environment(usageModel)
        .environment(quotaModel)
        .environment(codexQuotaResetModel)
        .environment(updateModel)
        .environment(breakReminderModel)
        .environment(inboxModel)
    }
}
