import SwiftUI

struct CodexQuotaResetView: View {
    @Environment(CodexQuotaModel.self) private var model
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
            .panelPopover(isPresented: $isPresented) {
                CodexQuotaResetDetail()
            }
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
                QuotaRefreshButton(isDisabled: model.isBusy) {
                    model.refresh(force: true)
                }
            }
            CodexQuotaResetStatus()
            if case .available(_, stale: .some) = model.state {
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

private struct CodexQuotaResetStatus: View {
    @Environment(CodexQuotaModel.self) private var model

    var body: some View {
        switch model.resetState {
        case .idle:
            EmptyView()
        case .confirming(let attempt, let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text("Use \"\(attempt.credit.title)\"?")
                    .fontWeight(.semibold)
                if let expiration = attempt.credit.expiresAt {
                    Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Does not expire")
                }
                Text("This consumes one reset for eligible usage limits. This can't be undone.")
                    .foregroundStyle(.secondary)
                if let failure {
                    Text("No reset was used. \(failureMessage(failure))")
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button("Use reset") { model.submitReset() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    Button("Cancel") { model.cancelReset() }
                }
            }
        case .submitting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Resetting usage and refreshing quota…")
            }
        case .completed(let outcome):
            Text(outcomeMessage(outcome))
        case .unconfirmed(_, let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text(failureMessage(failure))
                    .foregroundStyle(.orange)
                Text("Reset outcome not confirmed. Retry uses the same request to avoid spending twice.")
                    .foregroundStyle(.secondary)
                Button("Retry same reset") { model.submitReset() }
                    .disabled(model.isBusy)
            }
        }
    }

    private func outcomeMessage(_ outcome: CodexQuotaResetOutcome) -> String {
        switch outcome {
        case .reset, .alreadyRedeemed:
            "Reset used."
        case .nothingToReset:
            "No eligible usage to reset. No reset was used."
        case .noCredit:
            "This reset is no longer available."
        }
    }

    private func failureMessage(_ failure: CodexAppServer.Failure) -> String {
        switch failure {
        case .methodNotFound:
            "This Codex version cannot use resets. Update Codex, then retry."
        case .rpc(let code):
            "Codex returned an error (code \(code))."
        case .binaryNotFound:
            "Codex wasn't found. Install Codex, then retry."
        case .timedOut, .sessionFailed:
            "The Codex request failed. Try again."
        }
    }
}

private struct CodexQuotaResetCreditRow: View {
    private static let expiryWarning: TimeInterval = 48 * 3_600

    @Environment(CodexQuotaModel.self) private var model
    let credit: CodexQuotaSnapshot.ResetCredit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.title)
                        .fontWeight(.semibold)
                    if let expiration = credit.expiresAt {
                        let date = expiration.formatted(date: .abbreviated, time: .shortened)
                        Text(credit.canUse(at: timeline.date) ? "Expires \(date)" : "Expired \(date)")
                            .foregroundStyle(
                                expiration.timeIntervalSince(timeline.date) <= Self.expiryWarning
                                    ? Color.orange : .secondary
                            )
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
