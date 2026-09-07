import SwiftUI

struct CodexQuotaResetStatusView: View {
    @Environment(CodexQuotaModel.self) private var model

    var body: some View {
        switch model.resetState {
        case .idle:
            EmptyView()
        case .confirming(let attempt, let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text("Use \"\(attempt.credit.title ?? "Quota reset")\"?")
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
                        .disabled(model.isRefreshing)
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
                    .disabled(model.isRefreshing)
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

    private func failureMessage(_ failure: CodexQuotaResetFailure) -> String {
        switch failure {
        case .rpc(code: -32601):
            "This Codex version cannot use resets. Update Codex, then retry."
        case .rpc(let code):
            "Codex returned an error (code \(code))."
        case .unavailable(.binaryNotFound):
            "Codex wasn't found. Install Codex, then retry."
        case .unavailable:
            "The Codex request failed. Try again."
        }
    }
}
