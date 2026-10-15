import AppKit
import SwiftUI

struct AppProcessList: View {
    let groups: [AppProcessGroup]
    let sampledAt: SuspendingClock.Instant

    @State private var hoverPinnedOrder: [pid_t]?

    var body: some View {
        PanelSection("Processes") {
            VStack(spacing: 8) {
                ForEach(hoverOrderedGroups) { group in
                    AppProcessRow(group: group, sampledAt: sampledAt)
                }
            }
            .onPointerHover { isInside in
                hoverPinnedOrder = isInside ? groups.map(\.id) : nil
            }
        }
    }

    private var hoverOrderedGroups: [AppProcessGroup] {
        guard let hoverPinnedOrder else { return groups }
        let rank = Dictionary(uniqueKeysWithValues: zip(hoverPinnedOrder, 0...))
        return groups.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }
}

private struct AppProcessRow: View {
    let group: AppProcessGroup
    let sampledAt: SuspendingClock.Instant

    @State private var quittingProcessCount: Int?

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(path: group.iconPath)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .fontWeight(.semibold)

                Text("^[\(group.members.count) process](inflect: true)")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Measure(bytes: group.footprint).text)
                    .fontWeight(.semibold)

                let cpu = Measure(fraction: group.cpu).text
                let gpu = Measure(fraction: group.gpu).text
                Text("\(cpu) CPU, \(gpu) GPU")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            Button(action: quit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
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
            guard let quittingProcessCount else { return }
            self.quittingProcessCount = group.members.count < quittingProcessCount ? group.members.count : nil
        }
    }

    private var isQuitting: Bool { quittingProcessCount != nil }

    private func quit() {
        quittingProcessCount = group.members.count
        group.forceTerminate()
    }
}

/// a path-only view boundary avoids recreating and animating app icons on every sample.
private struct AppIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}
