import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var usageModel = UsageModel(usageService: UsageService())
    @State private var codexQuotaModel = CodexQuotaModel(quotaService: CodexQuotaService())
    @State private var grokQuotaModel = GrokQuotaModel(quotaService: GrokQuotaService())
    @State private var updateModel = UpdateModel()
    @State private var breakReminderModel = BreakReminderModel(
        notifications: BreakReminderNotificationCenter()
    )
    @State private var inboxModel = InboxModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(usageModel)
                .environment(codexQuotaModel)
                .environment(grokQuotaModel)
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
                .environment(usageModel)
                .environment(updateModel)
                .environment(breakReminderModel)
                .fontDesign(.rounded)
        }
        .windowResizability(.contentSize)
    }
}
