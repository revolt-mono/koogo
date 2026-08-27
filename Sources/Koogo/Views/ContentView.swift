import SwiftUI

struct ContentView: View {
    private let usageModel: UsageModel
    private let codexQuotaModel: CodexQuotaModel

    init(usageModel: UsageModel, codexQuotaModel: CodexQuotaModel) {
        self.usageModel = usageModel
        self.codexQuotaModel = codexQuotaModel
    }

    var body: some View {
        Group {
            if let snapshot = usageModel.snapshot {
                UsagePanelView(
                    snapshot: snapshot,
                    codexQuotaState: codexQuotaModel.state
                )
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
        .animation(.smooth(duration: 0.25), value: codexQuotaModel.state)
        .task {
            codexQuotaModel.refresh()
            await usageModel.refresh()
        }
    }
}
