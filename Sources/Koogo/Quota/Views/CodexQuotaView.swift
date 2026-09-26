import Shimmer
import SwiftUI

struct CodexQuotaView: View {
    @Environment(CodexQuotaModel.self) private var codexQuotaModel

    var body: some View {
        switch codexQuotaModel.state {
        case .unavailable:
            EmptyView()
        case .loading:
            VStack(spacing: 16) {
                CodexQuotaLoadingView()
                Divider()
            }
        case .available(let snapshot):
            VStack(spacing: 16) {
                CodexQuotaContent(snapshot: snapshot)
                if codexQuotaModel.refreshFailure != nil {
                    QuotaStaleNotice(isRefreshDisabled: codexQuotaModel.isRefreshing || codexQuotaModel.isResetting) {
                        codexQuotaModel.refresh(force: true)
                    }
                }
                Divider()
            }
        }
    }
}

private struct CodexQuotaContent: View {
    let snapshot: CodexQuotaSnapshot

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                if let limits = snapshot.account?.limits {
                    CodexQuotaLimitsView(title: nil, limits: limits)
                }
                CodexQuotaResetView()
            }

            ForEach(snapshot.models) { model in
                CodexQuotaLimitsView(title: model.title, limits: model.limits)
            }
        }
    }
}

private struct CodexQuotaLimitsView: View {
    let title: String?
    let limits: CodexQuotaSnapshot.Limits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                }
            }

            if let fiveHour = limits.fiveHour {
                QuotaWindowRow(
                    scopeTitle: title ?? "Codex",
                    title: "5h limit",
                    window: fiveHour
                )
            }
            if let weekly = limits.weekly {
                QuotaWindowRow(
                    scopeTitle: title ?? "Codex",
                    title: "Weekly limit",
                    window: weekly
                )
            }
        }
    }
}

private struct CodexQuotaLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    QuotaWindowPlaceholder()
                }
            }

            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 76, height: 8)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: 52, height: 8)
            }
        }
        .foregroundStyle(.secondary.opacity(0.24))
        .shimmering(active: !reduceMotion)
        .accessibilityLabel("Loading account limits")
    }
}
