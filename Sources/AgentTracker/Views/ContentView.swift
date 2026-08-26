import SwiftUI

struct ContentView: View {
    private let usageService: UsageService
    @State private var snapshot: UsageSnapshot?

    init(usageService: UsageService) {
        self.usageService = usageService
    }

    var body: some View {
        Group {
            if let snapshot {
                UsagePanelView(snapshot: snapshot)
                    .transition(.blurReplace)
            } else {
                UsageLoadingView()
                    .transition(.blurReplace)
            }
        }
        .fontDesign(.rounded)
        .frame(width: 300)
        .task {
            await refreshUsage()
        }
    }

    private func refreshUsage() async {
        while !Task.isCancelled {
            let refreshedSnapshot = await usageService.refresh()
            withAnimation(.smooth(duration: 0.35)) {
                snapshot = refreshedSnapshot
            }

            do {
                // TODO: Make this user-configurable after backend integration.
                let refreshDelay = min(
                    600,
                    max(0, refreshedSnapshot.validUntil.timeIntervalSinceNow)
                )
                try await Task.sleep(for: .seconds(refreshDelay))
            } catch {
                break
            }
        }
    }
}
