import AppKit
import SwiftUI

@main
struct KoogoApp: App {
    @State private var usageModel = UsageModel(usageService: UsageService())
    @State private var codexQuotaModel = CodexQuotaModel(quotaService: CodexQuotaService())
    @State private var updateModel = UpdateModel()
    @State private var breakReminderModel = BreakReminderModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(usageModel)
                .environment(codexQuotaModel)
                .environment(updateModel)
                .environment(breakReminderModel)
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
