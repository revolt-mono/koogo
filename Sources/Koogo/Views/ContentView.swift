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
            let tint = Color(
                .sRGB,
                red: 12.0 / 255,
                green: 21.0 / 255,
                blue: 22.0 / 255,
                opacity: 1
            )

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.94), location: 0),
                    .init(color: .black.opacity(0.92), location: 0.07),
                    .init(color: tint.opacity(0.7), location: 0.22),
                    .init(color: tint.opacity(0.4), location: 0.36),
                    .init(color: tint.opacity(0.16), location: 0.48),
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
