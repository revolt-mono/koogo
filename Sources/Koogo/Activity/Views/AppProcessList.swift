import AppKit
import SwiftUI

/// Hover is tracked once for the whole list: SwiftUI hit-tests every hover responder on each mouse move, so the pointer's row comes from the frames the rows report.
struct AppProcessList: View {
    fileprivate nonisolated static let rowSpace = "rows"

    let groups: [AppProcessGroup]
    let sampledAt: SuspendingClock.Instant

    @State private var rowFrames: [pid_t: CGRect] = [:]
    /// The row the pointer has rested on, which is when its quit button shows.
    @State private var restingID: pid_t?
    /// The order the pointer found the list in holds while the pointer stays, so no row moves out from under a click; groups arriving meanwhile queue at the end.
    @State private var pinnedOrder: [pid_t]?

    var body: some View {
        PanelSection("Processes") {
            VStack(spacing: 8) {
                ForEach(pinned) { group in
                    AppProcessRow(group: group, sampledAt: sampledAt, showsQuit: restingID == group.id)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Self.rowSpace))
                        } action: { frame in
                            rowFrames[group.id] = frame
                        }
                        .onDisappear { rowFrames[group.id] = nil }
                }
            }
            .coordinateSpace(.named(Self.rowSpace))
            .contentShape(.rect)
            .modifier(
                RestingHover(frames: rowFrames, restingID: $restingID) { isInside in
                    pinnedOrder = isInside ? groups.map(\.id) : nil
                }
            )
        }
    }

    private var pinned: [AppProcessGroup] {
        guard let pinnedOrder else { return groups }
        let rank = Dictionary(uniqueKeysWithValues: zip(pinnedOrder, 0...))
        return groups.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
    }
}

/// Keeps the pointer's momentary row out of the list's state, so crossing rows re-renders nothing there.
private struct RestingHover: ViewModifier {
    let frames: [pid_t: CGRect]
    @Binding var restingID: pid_t?
    let onHover: (Bool) -> Void

    @State private var hoveredID: pid_t?
    @State private var isInside = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .named(AppProcessList.rowSpace)) { phase in
                switch phase {
                case .active(let point):
                    let id = frames.first { $0.value.contains(point) }?.key
                    if hoveredID != id { hoveredID = id }
                    if !isInside {
                        isInside = true
                        onHover(true)
                    }
                case .ended:
                    hoveredID = nil
                    isInside = false
                    onHover(false)
                }
            }
            .task(id: hoveredID) {
                restingID = nil
                guard let hoveredID, (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
                restingID = hoveredID
            }
    }
}

private struct AppProcessRow: View {
    let group: AppProcessGroup
    let sampledAt: SuspendingClock.Instant
    let showsQuit: Bool

    /// The process count when the quit was asked and at each sample since that showed fewer; a sample showing no fewer means the quit stalled, and the row thaws.
    @State private var quittingFrom: Int?

    var body: some View {
        HStack(spacing: 8) {
            Group {
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
            }
            .displayOnly()

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
        .opacity(isQuitting ? 0.4 : 1)
        .motionAnimation(.easeOut(duration: 0.2), value: isQuitting)
        .motionAnimation(showsQuit ? .smooth(duration: 0.25) : .smooth(duration: 0.25).delay(0.08), value: showsQuit)
        .accessibilityAction(named: "Quit \(group.name)", quit)
        .onChange(of: sampledAt) {
            guard let quittingFrom else { return }
            self.quittingFrom = group.processCount < quittingFrom ? group.processCount : nil
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
