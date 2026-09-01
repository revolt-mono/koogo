import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var usageModel: UsageModel
    @State private var codexQuotaModel: CodexQuotaModel
    @State private var updateModel: UpdateModel
    @State private var breakReminderModel: BreakReminderModel
    @State private var inboxModel: InboxModel

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        _usageModel = State(initialValue: UsageModel(usageService: UsageService()))
        _codexQuotaModel = State(
            initialValue: CodexQuotaModel(quotaService: CodexQuotaService())
        )
        _updateModel = State(initialValue: UpdateModel())
        _breakReminderModel = State(
            initialValue: BreakReminderModel(
                notifications: BreakReminderNotificationCenter()
            )
        )
        _inboxModel = State(initialValue: InboxModel())
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(usageModel)
                .environment(codexQuotaModel)
                .environment(updateModel)
                .environment(breakReminderModel)
                .environment(inboxModel)
                .fontDesign(.rounded)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(updateModel)
                .environment(breakReminderModel)
                .fontDesign(.rounded)
        }
        .windowResizability(.contentSize)
    }
}
