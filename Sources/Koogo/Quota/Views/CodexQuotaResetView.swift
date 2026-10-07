import SwiftUI

struct CodexQuotaResetView: View {
    @Environment(CodexQuotaResetModel.self) private var model

    var body: some View {
        if model.isShown {
            PanelDisclosure {
                HStack(spacing: 4) {
                    if let credits = model.credits {
                        let noun = credits.availableCount == 1 ? "banked reset" : "banked resets"
                        Text("\(Text("\(credits.availableCount)").foregroundStyle(.white)) \(noun) available")
                            .monospacedDigit()
                    } else {
                        Text("Banked resets")
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } content: {
                CodexQuotaResetDetail()
            }
            .accessibilityLabel("Banked reset details")
        }
    }
}

private struct CodexQuotaResetDetail: View {
    @Environment(CodexQuotaResetModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Banked resets").font(.headline)
                if let credits = model.credits {
                    Text("\(credits.availableCount) available")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CodexQuotaRefreshButton(isDisabled: model.isBusy, action: model.refresh)
            }
            CodexQuotaResetStatus()
            if let credits = model.credits?.credits, !credits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(credits) { credit in
                        if credit.id != credits.first?.id {
                            Divider()
                        }
                        CodexQuotaResetCreditRow(credit: credit)
                    }
                }
            } else if let credits = model.credits, credits.availableCount > 0 {
                Text("Banked reset details are unavailable. Refresh to load them.")
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
    @Environment(CodexQuotaResetModel.self) private var model

    var body: some View {
        switch model.flow {
        case .idle:
            EmptyView()
        case .confirming(let attempt, let rejection):
            VStack(alignment: .leading, spacing: 8) {
                Text("Use \"\(attempt.credit.title)\"?")
                    .fontWeight(.semibold)
                if let expiration = attempt.credit.expiresAt {
                    Text("Expires \(expiration.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Does not expire")
                }
                Text("This consumes one banked reset for eligible usage limits. This can't be undone.")
                    .foregroundStyle(.secondary)
                if let rejection {
                    Text("No banked reset was used. \(failureMessage(rejection))")
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button("Use banked reset", action: model.submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    Button("Cancel", action: model.cancel)
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
                Button("Retry same reset", action: model.submit)
                    .disabled(model.isBusy)
            }
        }
    }

    private func outcomeMessage(_ outcome: CodexQuotaResetOutcome) -> String {
        switch outcome {
        case .reset, .alreadyRedeemed:
            "Banked reset used."
        case .nothingToReset:
            "No eligible usage to reset. No banked reset was used."
        case .noCredit:
            "This banked reset is no longer available."
        }
    }

    private func failureMessage(_ failure: ToolFailure) -> String {
        switch failure {
        case .rpc(code: -32601):
            "This Codex version cannot use banked resets. Update Codex, then retry."
        case .rpc(let code):
            "Codex returned an error (code \(code))."
        case .notFound:
            "Codex wasn't found. Install Codex, then retry."
        case .timedOut, .cancelled, .closed, .invalidMessage:
            "The Codex request failed. Try again."
        }
    }
}

private struct CodexQuotaResetCreditRow: View {
    private static let expiryWarning: TimeInterval = 48 * 3_600

    @Environment(CodexQuotaResetModel.self) private var model
    let credit: QuotaSnapshot.ResetCredit

    var body: some View {
        // The timeline only re-evaluates the row; the model's clock decides expiry.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credit.title)
                        .fontWeight(.semibold)
                    if let expiration = credit.expiresAt {
                        let date = expiration.formatted(date: .abbreviated, time: .shortened)
                        Text(credit.canUse(at: model.now) ? "Expires \(date)" : "Expired \(date)")
                            .foregroundStyle(
                                expiration.timeIntervalSince(model.now) <= Self.expiryWarning
                                    ? Color.orange : .secondary
                            )
                    } else {
                        Text("Does not expire").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Use") { model.begin(creditID: credit.id) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canUse(credit))
            }
        }
    }
}

private struct CodexQuotaRefreshButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Refresh")
        .disabled(isDisabled)
    }
}
