import SwiftUI

struct ClaudeQuotaView: View {
    @Environment(ClaudeQuotaModel.self) private var model

    var body: some View {
        switch model.state {
        case .unavailable:
            EmptyView()
        case .loading:
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { _ in
                        QuotaWindowPlaceholder()
                    }
                }
                .foregroundStyle(.secondary.opacity(0.24))
                .loadingShimmer()
                .accessibilityLabel("Loading Claude limits")
                Divider()
            }
        case .available(let snapshot, let stale):
            VStack(spacing: 16) {
                if let limits = snapshot.account {
                    QuotaLimitsView(provider: "Claude", limits: limits)
                }
                ForEach(snapshot.models) { model in
                    QuotaLimitsView(provider: "Claude", model: model.title, limits: model.limits)
                }
                if stale != nil {
                    QuotaStaleNotice(isRefreshDisabled: model.isRefreshing) {
                        model.refresh(force: true)
                    }
                }
                Divider()
            }
        }
    }
}
