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

    private var resetCredits: CodexQuotaSnapshot.ResetCredits? {
        model.snapshot?.account?.resetCredits
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Quota resets").font(.headline)
                if let resetCredits {
                    Text("\(resetCredits.availableCount) available")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CodexQuotaRefreshButton()
            }
            CodexQuotaResetStatusView()
            if model.refreshFailure != nil {
                Text("Quota data may be out of date. Refresh to check the latest limits and resets.")
                    .foregroundStyle(.orange)
            }
            if let credits = resetCredits?.credits, !credits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(credits) { credit in
                        if credit.id != credits.first?.id {
                            Divider()
                        }
                        CodexQuotaResetCreditRow(credit: credit)
                    }
                }
            } else if let resetCredits, resetCredits.availableCount > 0 {
                Text("Reset details are unavailable. Refresh to load them.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .controlSize(.small)
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CodexQuotaResetCreditRow: View {
    @Environment(CodexQuotaModel.self) private var model
    let credit: CodexQuotaSnapshot.ResetCredit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.title)
                        .fontWeight(.semibold)
                    if let expiration = credit.expiresAt {
                        let seconds = expiration.timeIntervalSince(timeline.date)
                        let date = expiration.formatted(date: .abbreviated, time: .shortened)
                        Text(seconds <= 0 ? "Expired \(date)" : "Expires \(date)")
                            .foregroundStyle(seconds <= 172_800 ? Color.orange : .secondary)
                    } else {
                        Text("Does not expire").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Use") { model.beginReset(creditID: credit.id) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canChooseReset || !credit.canUse(at: timeline.date))
            }
        }
    }
}
