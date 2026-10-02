import SwiftUI

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
        case .available(let snapshot):
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(snapshot.windows, id: \.title) { window in
                        QuotaWindowRow(provider: provider, window: window)
                    }
                    if let credits = snapshot.credits {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Credits")
                                .fontWeight(.semibold)
                            Spacer(minLength: 12)
                            switch credits {
                            case .balance(let balance):
                                Text(balance, format: .number.precision(.fractionLength(0...2)))
                            case .available:
                                Text("Available")
                            case .unlimited:
                                Text("Unlimited")
                            }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                    }
                    if provider == .codex {
                        CodexQuotaResetView()
                    }
                }
                Divider()
            }
        }
    }
}
