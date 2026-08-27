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
        .animation(.smooth(duration: 0.35), value: usageModel.snapshot)
        .animation(.smooth(duration: 0.25), value: codexQuotaModel.state)
        .task {
            codexQuotaModel.refresh()
            usageModel.refresh()
        }
    }
}
