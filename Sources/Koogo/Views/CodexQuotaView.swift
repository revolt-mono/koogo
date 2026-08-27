import Shimmer
import SwiftUI

struct CodexQuotaView: View {
    let state: CodexQuotaModel.State

    @ViewBuilder
    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .loading:
            quotaSection {
                CodexQuotaLoadingView()
            }
        case .available(let snapshot):
            quotaSection {
                CodexQuotaContent(snapshot: snapshot)
            }
        }
    }

    private func quotaSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            content()
            Divider()
        }
    }
}

private struct CodexQuotaContent: View {
    let snapshot: CodexQuotaSnapshot

    var body: some View {
        VStack(spacing: 12) {
            if !snapshot.limits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(snapshot.limits, id: \.period) { limit in
                        let title = switch limit.period {
                        case .fiveHour: "5h limit"
                        case .weekly: "Weekly limit"
                        }

                        CodexQuotaWindowRow(
                            title: title,
                            window: limit.window
                        )
                    }
                }
            }

            if let availableResetCount = snapshot.availableResetCount {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Quota reset")
                        .fontWeight(.semibold)

                    Spacer(minLength: 12)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(availableResetCount)")
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(" available")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 9, weight: .medium))
            }
        }
    }
}

private struct CodexQuotaWindowRow: View {
    let title: String
    let window: CodexQuotaSnapshot.Window

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)

                Spacer(minLength: 12)

                Text("\(window.remainingPercent)% left")
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if let resetsAt = window.resetsAt {
                    Text("· resets \(resetText(resetsAt))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .progressViewStyle(CodexQuotaProgressViewStyle())
                .accessibilityLabel(title)
                .accessibilityValue("\(window.remainingPercent) percent left")
        }
    }

    private func resetText(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "HH:mm 'on' d MMM"
        return formatter.string(from: date)
    }
}

private struct CodexQuotaProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary,
                                Color.primary.opacity(0.42),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}

private struct CodexQuotaLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(spacing: 4) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: 44, height: 8)
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .frame(width: 104, height: 8)
                        }
                        RoundedRectangle(cornerRadius: 2)
                            .frame(height: 6)
                    }
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
