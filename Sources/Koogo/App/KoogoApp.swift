import SwiftUI

@main
struct KoogoApp: App {
    @State private var usageModel = UsageModel(usageService: UsageService())

    var body: some Scene {
        MenuBarExtra {
            ContentView(usageModel: usageModel)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
