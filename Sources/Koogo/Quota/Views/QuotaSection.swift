import SwiftUI

/// One provider's quota inside its usage card: placeholders while loading, the windows once read, and a
/// stale notice after a failed refresh. Nothing for a provider that is switched off or has no quota.
struct QuotaSection: View {
    @Environment(QuotaModel.self) private var quotaModel
    let provider: Provider

    var body: some View {
        switch quotaModel.states[provider] {
        case nil, .unavailable:
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
                .accessibilityLabel("Loading \(provider.title) limits")
                Divider()
            }
        case .available(let snapshot, let stale):
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    if !snapshot.account.isEmpty {
                        QuotaWindowsView(scopeTitle: provider.title, windows: snapshot.account)
                    }
                    if provider == .codex {
                        CodexQuotaResetView()
                    }
                }
                ForEach(snapshot.models) { model in
                    QuotaWindowsView(
                        scopeTitle: "\(provider.title) \(model.title)",
                        header: model.title,
                        windows: model.windows
                    )
                }
                if stale != nil {
                    QuotaStaleNotice(isRefreshDisabled: quotaModel.isBusy(provider)) {
                        quotaModel.refresh(provider, force: true)
                    }
                }
                Divider()
            }
        }
    }
}
