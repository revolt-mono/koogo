import SwiftUI

struct ContentView: View {
    private let usageModel: UsageModel

    init(usageModel: UsageModel) {
        self.usageModel = usageModel
    }

    var body: some View {
        Group {
            if let snapshot = usageModel.snapshot {
                UsagePanelView(snapshot: snapshot)
                    .transition(.blurReplace)
            } else {
                UsageLoadingView()
                    .transition(.blurReplace)
            }
        }
        .fontDesign(.rounded)
        .frame(width: 300)
        .animation(.smooth(duration: 0.35), value: usageModel.snapshot)
        .task {
            await usageModel.refresh()
        }
    }
}
