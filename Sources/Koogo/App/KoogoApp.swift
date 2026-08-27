import AppKit
import SwiftUI

@main
struct KoogoApp: App {
    @State private var usageModel = UsageModel(usageService: UsageService())

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(usageModel: usageModel)
                .fontDesign(.rounded)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
