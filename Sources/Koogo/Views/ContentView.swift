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
        .frame(width: 300)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0),
                    .init(color: .black.opacity(0.52), location: 0.16),
                    .init(color: .black.opacity(0.22), location: 0.36),
                    .init(color: .clear, location: 0.62),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.smooth(duration: 0.35), value: usageModel.snapshot)
        .task {
            await usageModel.refresh()
        }
    }
}
