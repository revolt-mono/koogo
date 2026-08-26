import SwiftUI

@main
struct AgentTrackerApp: App {
    private let usageService = UsageService()

    var body: some Scene {
        MenuBarExtra {
            ContentView(usageService: usageService)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
