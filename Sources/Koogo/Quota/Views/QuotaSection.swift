import SwiftUI

struct QuotaSection: View {
  let provider: QuotaProvider

  var body: some View {
    let snapshot = quotaModel.snapshot(of: provider)
    let showsReset =
      provider == .codex && (quotaModel.codexResetCredits != nil || quotaModel.codexReset != .idle)
    // The reset row already explains a denied reset.
    let denial: ProviderUpstreamAccess.Denial? =
      if !showsReset, case .paused(let reason) = quotaModel.statuses[provider].latest {
        reason
      } else {
        nil
      }
    if snapshot != nil || showsReset || denial != nil {
      VStack(spacing: 16) {
        VStack(spacing: 8) {
          if let denial {
            Text(denial.message)
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if let snapshot {
            ForEach(snapshot.windows.enumerated(), id: \.offset) { _, window in
              QuotaWindowRow(provider: provider.provider, window: window)
            }
            if let credits = snapshot.credits {
              QuotaCreditsRow(credits: credits)
            }
          }
          if showsReset {
            CodexQuotaResetView()
          }
        }
        Divider()
      }
    }
  }

  @Environment(QuotaModel.self) private var quotaModel
}

private struct QuotaWindowRow: View {
  let provider: Provider
  let window: QuotaWindow

  var body: some View {
    VStack(spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(window.title)
          .fontWeight(.semibold)

        Spacer(minLength: 12)

        RollingText(text: "\(window.usedPercent)% used")
          .foregroundStyle(.primary)
          .monospacedDigit()

        if let resetsAt = window.resetsAt {
          QuotaDeadlineLabel(deadline: resetsAt)
        }
      }
      .font(.system(size: 9, weight: .medium))
      .lineLimit(1)

      ProgressView(value: Double(window.usedPercent), total: 100)
        .progressViewStyle(.panel)
        .accessibilityLabel("\(provider.title) \(window.title)")
        .accessibilityValue("\(window.usedPercent) percent used")
    }
  }
}

private struct QuotaCreditsRow: View {
  let credits: QuotaSnapshot.Credits

  var body: some View {
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
}

private struct QuotaDeadlineLabel: View {
  let deadline: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { timeline in
      Text("resets \(deadline.formatted(.timeRemaining(from: timeline.date)))")
    }
    .foregroundStyle(.secondary)
    .tooltip(deadline.formatted(.display(date: .complete, time: .shortened)))
  }
}
