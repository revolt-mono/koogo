import SwiftUI

struct CodexQuotaResetView: View {
    @Environment(CodexQuotaModel.self) private var model
    @Environment(\.isSelectedPanelPage) private var isSelectedPanelPage
    @State private var isPresented = false

    var body: some View {
        if model.snapshot?.account?.resetCredits != nil || model.resetState != .idle {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("Quota reset")
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if let credits = model.snapshot?.account?.resetCredits {
                        Text("\(Text(credits.availableCount.formatted()).foregroundStyle(.white)) available")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quota reset details")
            .accessibilityValue(isPresented ? "Expanded" : "Collapsed")
            .background {
                PopoverClickBoundary().allowsHitTesting(false)
            }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                CodexQuotaResetDetail()
            }
            .onChange(of: isSelectedPanelPage) {
                if !isSelectedPanelPage { isPresented = false }
            }
            .onDisappear { isPresented = false }
        }
    }
}

private struct CodexQuotaResetDetail: View {
    @Environment(CodexQuotaModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quota resets").font(.headline)
                Spacer()
                CodexQuotaRefreshButton()
            }
            CodexQuotaResetStatusView()
            if model.refreshFailure != nil {
                Text("Quota data may be out of date. Refresh to check the latest limits and resets.")
                    .foregroundStyle(.orange)
            }
            if let summary = model.snapshot?.account?.resetCredits {
                Text("\(summary.availableCount) available")
                    .foregroundStyle(.secondary)
                if let credits = summary.credits, !credits.isEmpty {
                    ForEach(credits) { credit in
                        CodexQuotaResetCreditView(credit: credit)
                    }
                } else if summary.availableCount > 0 {
                    Text("Reset details are unavailable. Refresh to load them.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CodexQuotaResetCreditView: View {
    @Environment(CodexQuotaModel.self) private var model
    let credit: CodexQuotaSnapshot.ResetCredit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(credit.title ?? "Quota reset")
                        .fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Button("Use") { model.beginReset(creditID: credit.id) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canChooseReset || !credit.canUse(at: timeline.date))
                }
                if let expiration = credit.expiresAt {
                    let seconds = expiration.timeIntervalSince(timeline.date)
                    Text(expiration.formatted(date: .abbreviated, time: .shortened))
                    Text(
                        seconds <= 0
                            ? "Expired" : "Expires \(quotaTimeRemainingText(until: expiration, now: timeline.date))"
                    )
                    .foregroundStyle(seconds <= 172_800 ? Color.orange : .secondary)
                    .monospacedDigit()
                } else {
                    Text("Does not expire").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
