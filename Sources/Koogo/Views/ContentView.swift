import SwiftUI

struct ContentView: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(CodexQuotaModel.self) private var codexQuotaModel

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
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.78), location: 0.12),
                    .init(color: .black.opacity(0.58), location: 0.24),
                    .init(color: .black.opacity(0.32), location: 0.38),
                    .init(color: .black.opacity(0.12), location: 0.5),
                    .init(color: .clear, location: 0.6),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.smooth(duration: 0.35), value: usageModel.snapshot != nil)
        .task {
            codexQuotaModel.refresh()
            usageModel.refresh()
        }
    }
}
