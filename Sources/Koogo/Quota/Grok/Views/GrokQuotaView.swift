import SwiftUI

struct GrokQuotaView: View {
    @Environment(GrokQuotaModel.self) private var model

    var body: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 16) {
                QuotaWindowPlaceholder()
                    .foregroundStyle(.secondary.opacity(0.24))
                    .loadingShimmer()
                    .accessibilityLabel("Loading Grok limits")
                Divider()
            }
        case .unavailable:
            EmptyView()
        case .available(let snapshot, let stale):
            let title =
                switch snapshot.period {
                case .weekly: "Weekly"
                case .monthly: "Monthly limit"
                case nil: "Usage limit"
                }
            VStack(spacing: 16) {
                QuotaWindowRow(scopeTitle: "Grok", title: title, window: snapshot.window)
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
