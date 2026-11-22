import SwiftUI

struct CodexQuotaResetView: View {
  var body: some View {
    PanelDisclosure {
      HStack(spacing: 4) {
        if let credits = quota.codexResetCredits {
          let noun = credits.availableCount == 1 ? "banked reset" : "banked resets"
          Text("\(Text("\(credits.availableCount)").foregroundStyle(.panelLabel)) \(noun) available")
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

  @Environment(QuotaModel.self) private var quota
}

private struct CodexQuotaResetDetail: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Banked resets")
          .fontWeight(.semibold)
        if let credits = quota.codexResetCredits {
          Text("\(credits.availableCount) available")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          quota.reload([.codex])
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 11, weight: .medium))
            .frame(width: 16, height: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Refresh")
        .disabled(quota.statuses[.codex].isBusy)
      }
      CodexQuotaResetStatus()
      if let credits = quota.codexResetCredits?.credits, !credits.isEmpty {
        VStack(spacing: 8) {
          ForEach(credits) { credit in
            if credit.id != credits.first?.id {
              Divider()
            }
            CodexQuotaResetCreditRow(credit: credit)
          }
        }
      } else if let credits = quota.codexResetCredits, credits.availableCount > 0 {
        Text("Banked reset details are unavailable. Refresh to load them.")
          .foregroundStyle(.secondary)
      }
    }
    .controlSize(.small)
  }

  @Environment(QuotaModel.self) private var quota
}

private struct CodexQuotaResetStatus: View {
  var body: some View {
    switch quota.codexReset {
    case .idle:
      EmptyView()

    case .confirming(let attempt, let rejection):
      CodexQuotaResetConfirmation(credit: attempt.credit, rejection: rejection)

    case .submitting:
      HStack(spacing: 8) {
        ProgressView()
        Text("Resetting usage and refreshing quota…")
      }

    case .completed(let outcome):
      Text(outcome.message)

    case .unconfirmed(_, let failure):
      CodexQuotaResetRetry(failure: failure)
    }
  }

  @Environment(QuotaModel.self) private var quota
}

private struct CodexQuotaResetConfirmation: View {
  let credit: QuotaSnapshot.ResetCredit
  let rejection: ToolFailure?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Use \"\(credit.title)\"?")
        .fontWeight(.semibold)
      if let expiration = credit.expiresAt {
        Text("Expires \(expiration.formatted(.display(date: .abbreviated, time: .shortened)))")
      } else {
        Text("Does not expire")
      }
      Text("This consumes one banked reset for eligible usage limits. This can't be undone.")
        .foregroundStyle(.secondary)
      if let rejection {
        Text("No banked reset was used. \(rejection.codexResetMessage)")
          .foregroundStyle(.orange)
      }
      HStack(spacing: 8) {
        Button("Use banked reset", action: quota.submitCodexReset)
          .buttonStyle(.borderedProminent)
          .disabled(quota.statuses[.codex].isBusy)
        Button("Cancel", action: quota.cancelCodexReset)
      }
    }
  }

  @Environment(QuotaModel.self) private var quota
}

private struct CodexQuotaResetRetry: View {
  let failure: ToolFailure

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(failure.codexResetMessage)
        .foregroundStyle(.orange)
      Text("Reset outcome not confirmed. Retry uses the same request to avoid spending twice.")
        .foregroundStyle(.secondary)
      Button("Retry same reset", action: quota.submitCodexReset)
        .disabled(quota.statuses[.codex].isBusy)
    }
  }

  @Environment(QuotaModel.self) private var quota
}

private struct CodexQuotaResetCreditRow: View {
  let credit: QuotaSnapshot.ResetCredit

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { _ in
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(credit.title)
            .fontWeight(.semibold)
          if let expiration = credit.expiresAt {
            let now = quota.now()
            let date = expiration.formatted(.display(date: .abbreviated, time: .shortened))
            Text(credit.canUse(at: now) ? "Expires \(date)" : "Expired \(date)")
              .foregroundStyle(
                expiration.timeIntervalSince(now) <= Self.expiryWarning
                  ? Color.orange
                  : .secondary
              )
          } else {
            Text("Does not expire").foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Use") { quota.beginCodexReset(creditID: credit.id) }
          .buttonStyle(.borderedProminent)
          .disabled(!quota.canUseCodexReset(credit))
      }
    }
  }

  private static let expiryWarning: TimeInterval = 48 * 3_600

  @Environment(QuotaModel.self) private var quota
}

extension CodexQuotaResetOutcome {
  fileprivate var message: String {
    switch self {
    case .reset,
         .alreadyRedeemed:
      "Banked reset used."
    case .nothingToReset:
      "No eligible usage to reset. No banked reset was used."
    case .noCredit:
      "This banked reset is no longer available."
    }
  }
}

extension ToolFailure {
  fileprivate var codexResetMessage: String {
    switch self {
    case .methodNotFound:
      "This Codex version cannot use banked resets. Update Codex, then retry."
    case .rpc(let code):
      "Codex returned an error (code \(code))."
    case .notFound:
      "Codex wasn't found. Install Codex, then retry."
    case .timedOut,
         .closed,
         .invalidMessage:
      "The Codex request failed. Try again."
    }
  }
}
