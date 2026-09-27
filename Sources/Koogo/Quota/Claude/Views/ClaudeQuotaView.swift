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
                VStack(spacing: 8) {
                    if let session = snapshot.session {
                        QuotaWindowRow(scopeTitle: "Claude", title: "Session", window: session)
                    }
                    if let weekly = snapshot.weekly {
                        QuotaWindowRow(scopeTitle: "Claude", title: "Weekly", window: weekly)
                    }
                }
                ForEach(snapshot.models) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        QuotaScopeHeader(title: model.title)
                        QuotaWindowRow(scopeTitle: "Claude \(model.title)", title: "Weekly", window: model.weekly)
                    }
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
