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
            .onHover { pinnedOrder = $0 ? groups.map(\.id) : nil }
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

    @State private var isHovered = false
    @State private var showsQuit = false
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

            if showsQuit && !isQuitting {
                Button(action: quit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quit \(group.name)")
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.4).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.08))
                    )
                )
            }
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
        .contentShape(.rect)
        .opacity(isQuitting ? 0.4 : 1)
        .motionAnimation(.easeOut(duration: 0.2), value: isQuitting)
        .motionAnimation(showsQuit ? .smooth(duration: 0.25) : .smooth(duration: 0.25).delay(0.08), value: showsQuit)
        .accessibilityAction(named: "Quit \(group.name)", quit)
        .onChange(of: sampledAt) {
            guard let quittingFrom else { return }
            self.quittingFrom = group.processCount < quittingFrom ? group.processCount : nil
        }
        .onHover { isHovered = $0 }
        .task(id: isHovered) {
            showsQuit = false
            guard isHovered, (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            showsQuit = true
        }
    }

    private var isQuitting: Bool { quittingFrom != nil }

    private func quit() {
        quittingFrom = group.processCount
        group.terminate()
    }
}

/// Keyed on the path alone; a fresh `NSImage` per row body would redraw and animate the icon on every hover.
private struct AppIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
