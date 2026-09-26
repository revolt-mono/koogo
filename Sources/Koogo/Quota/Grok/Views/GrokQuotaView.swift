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
        case .unavailable(.credentialsExpired):
            VStack(spacing: 16) {
                GrokSessionExpiredHint()
                Divider()
            }
        case .unavailable:
            EmptyView()
        case .available(let snapshot, let stale):
            let title =
                switch snapshot.period {
                case .weekly: "Weekly limit"
                case .monthly: "Monthly limit"
                case nil: "Usage limit"
                }
            VStack(spacing: 16) {
                QuotaWindowRow(scopeTitle: "Grok", title: title, window: snapshot.window)
                switch stale {
                case nil:
                    EmptyView()
                case .credentialsExpired:
                    // Refreshing cannot help until the Grok CLI renews its session.
                    GrokSessionExpiredHint()
                case .some:
                    QuotaStaleNotice(isRefreshDisabled: model.isRefreshing) {
                        model.refresh(force: true)
                    }
                }
                Divider()
            }
        }
    }
}

private struct GrokSessionExpiredHint: View {
    var body: some View {
        Text("Run grok to refresh its quota")
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
