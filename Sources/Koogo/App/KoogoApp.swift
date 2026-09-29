import AppKit
import SwiftUI

struct KoogoApp: App {
    @State private var usageModel: UsageModel
    @State private var codexQuotaModel = CodexQuotaModel(quotaService: CodexQuotaService())
    @State private var claudeQuotaModel = ClaudeQuotaModel(quotaService: ClaudeQuotaService())
    @State private var grokQuotaModel = GrokQuotaModel(quotaService: GrokQuotaService())
    @State private var updateModel: UpdateModel
    @State private var breakReminderModel = BreakReminderModel(
        notifications: BreakReminderNotificationCenter()
    )
    @State private var inboxModel = InboxModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let usageModel = UsageModel(usageService: UsageService())
        // Reading every log in the history window is the slowest step in the app, so it starts at launch
        // and the first panel open finds a snapshot instead of the parsing placeholder.
        usageModel.refresh()
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
        .environment(usageModel)
        .environment(codexQuotaModel)
        .environment(claudeQuotaModel)
        .environment(grokQuotaModel)
        .environment(updateModel)
        .environment(breakReminderModel)
        .environment(inboxModel)
    }
}
