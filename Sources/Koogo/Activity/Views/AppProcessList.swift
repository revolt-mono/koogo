import AppKit
import SwiftUI

struct AppProcessList: View {
    let groups: [AppProcessGroup]
    let sampledAt: SuspendingClock.Instant

    /// The order the pointer found the list in holds while the pointer stays, so no row moves out from under a click; groups arriving meanwhile queue at the end.
    @State private var pinnedOrder: [pid_t]?

    var body: some View {
        PanelSection("Processes") {
            VStack(spacing: 8) {
                ForEach(pinned) { group in
                    AppProcessRow(group: group, sampledAt: sampledAt)
                }
            }
            .onPointerHover { isInside in
                pinnedOrder = isInside ? groups.map(\.id) : nil
            }
        }
    }

    private var pinned: [AppProcessGroup] {
        guard let pinnedOrder else { return groups }
        let rank = Dictionary(uniqueKeysWithValues: zip(pinnedOrder, 0...))
        return groups.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }
}

private struct AppProcessRow: View {
    let group: AppProcessGroup
    let sampledAt: SuspendingClock.Instant

    /// The process count when the quit was asked and at each sample since that showed fewer; a sample showing no fewer means the quit stalled, and the row thaws.
    @State private var quittingFrom: Int?

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(path: group.iconPath)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .fontWeight(.semibold)

                Text("^[\(group.processCount) process](inflect: true)")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ActivityFormatting.bytes(group.footprint).text)
                    .fontWeight(.semibold)

                let cpu = ActivityFormatting.percent(group.cpu).text
                let gpu = ActivityFormatting.percent(group.gpu).text
                Text("\(cpu) CPU, \(gpu) GPU")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            Button(action: quit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isQuitting)
            .accessibilityLabel("Quit \(group.name)")
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
        .opacity(isQuitting ? 0.4 : 1)
        .motionAnimation(.easeOut(duration: 0.2), value: isQuitting)
        .onChange(of: sampledAt) {
            guard let quittingFrom else { return }
            self.quittingFrom = group.processCount < quittingFrom ? group.processCount : nil
        }
    }

    private var isQuitting: Bool { quittingFrom != nil }

    private func quit() {
        quittingFrom = group.processCount
        group.forceTerminate()
    }
}

/// Keyed on the path alone; a fresh `NSImage` per row body would redraw and animate the icon on every sample.
private struct AppIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
