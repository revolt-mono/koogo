import AppKit
import SwiftUI

struct AppProcessList: View {
    let groups: [AppProcessGroup]
    let sampledAt: SuspendingClock.Instant

    @State private var hoverPinnedOrder: [pid_t]?
    @State private var expanded: Set<pid_t> = []

    var body: some View {
        PanelSection("Processes") {
            LazyVStack(spacing: 8) {
                ForEach(hoverOrderedGroups) { group in
                    AppProcessRow(group: group, sampledAt: sampledAt, isExpanded: expanded.contains(group.id)) {
                        expanded.formSymmetricDifference([group.id])
                    }
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
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var quittingProcessCount: Int?

    var body: some View {
        let summary = AppProcessSummary(
            name: group.name,
            iconPath: group.iconPath,
            processCount: group.members.count,
            footprint: Measure(bytes: group.footprint).text,
            load: "\(Measure(fraction: group.cpu).text) CPU, \(Measure(fraction: group.gpu).text) GPU",
            isExpanded: hasTree ? isExpanded : nil
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if hasTree {
                    Button(action: toggle) {
                        summary.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showsTree ? "Collapses the process tree" : "Expands the process tree")
                } else {
                    summary
                }

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

            if showsTree {
                AppProcessTree(members: group.members)
                    .padding(.leading, 28)
                    .padding(.trailing, 20)
            }
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

    private var hasTree: Bool { group.members.count > 1 }

    private var showsTree: Bool { hasTree && isExpanded }

    private func quit() {
        quittingProcessCount = group.members.count
        group.forceTerminate()
    }
}

/// displayed text only, so samples that leave a row's text unchanged skip rebuilding it.
private struct AppProcessSummary: View, Equatable {
    let name: String
    let iconPath: String
    let processCount: Int
    let footprint: String
    let load: String
    /// nil when the group has no tree to expand.
    let isExpanded: Bool?

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(path: iconPath)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.semibold)

                HStack(spacing: 2) {
                    Text("^[\(processCount) process](inflect: true)")

                    if let isExpanded {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(footprint)
                    .fontWeight(.semibold)

                Text(load)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .layoutPriority(1)
        }
    }
}

private struct AppProcessTree: View {
    let members: [AppProcessMember]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 4, verticalSpacing: 2) {
            ForEach(members.indices, id: \.self) { index in
                let member = members[index]
                GridRow {
                    HStack(spacing: 0) {
                        Text(guide(at: index))
                            .monospaced()
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                            .accessibilityHidden(true)

                        Text(member.name)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)

                    Text(Measure(fraction: member.cpu).text)
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    Text(Measure(bytes: member.footprint).text)
                        .fixedSize()
                }
            }
        }
        .monospacedDigit()
    }

    private func guide(at index: Int) -> String {
        let depth = members[index].depth
        guard depth > 0 else { return "" }
        let hasLaterSibling = { (level: Int) -> Bool in
            members[(index + 1)...].first { $0.depth <= level }?.depth == level
        }
        let lines = (1..<depth).map { hasLaterSibling($0) ? "│ " : "  " }.joined()
        return lines + (hasLaterSibling(depth) ? "├ " : "└ ")
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
