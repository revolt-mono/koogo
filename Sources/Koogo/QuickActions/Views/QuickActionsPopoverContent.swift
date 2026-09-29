import AppKit
import Combine
import SwiftUI

struct QuickActionsPopoverContent: View {
    @State private var systemAppearance = QuickActionModel(perform: SystemAppearance.toggle)
    @State private var diskImages = QuickActionModel(scan: MountedDiskImages.mounted) { try await $0.eject() }
    @State private var agentProcesses = QuickActionModel(scan: OrphanedAgentProcesses.running) {
        try await $0.terminate()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 2)

            QuickActionRow(model: systemAppearance, systemImage: "circle.lefthalf.filled") { phase in
                switch phase {
                case .scanning, .idle, .ready:
                    QuickActionCopy(title: "Toggle System Appearance", detail: "Switch macOS light and dark mode")
                case .performing:
                    QuickActionCopy(title: "Changing System Appearance", detail: "Waiting for System Events")
                case .failed(let message):
                    QuickActionCopy(title: "System Appearance Failed", detail: message)
                }
            }

            QuickActionRow(model: diskImages, systemImage: "eject") { phase in
                switch phase {
                case .scanning:
                    QuickActionCopy(title: "Checking Disk Images", detail: "Looking for visible mounted DMGs")
                case .idle:
                    QuickActionCopy(title: "No Mounted DMGs", detail: "Visible disk images appear here")
                case .ready(let diskImages):
                    QuickActionCopy(
                        title: "Eject \(plural(diskImages.values.count, "Mounted DMG"))",
                        detail: diskImages.values.map(\.name).joined(separator: ", ")
                    )
                case .performing(let diskImages):
                    QuickActionCopy(
                        title: "Ejecting \(plural(diskImages.values.count, "DMG"))",
                        detail: "Waiting for macOS"
                    )
                case .failed(let message):
                    QuickActionCopy(title: "Retry Disk Image Scan", detail: message)
                }
            }
            .onReceive(
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification),
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
                )
            ) { _ in
                diskImages.refresh()
            }

            QuickActionRow(model: agentProcesses, systemImage: "xmark.octagon") { phase in
                switch phase {
                case .scanning:
                    QuickActionCopy(
                        title: "Checking Agent Processes",
                        detail: "Looking for orphaned claude, codex, and grok"
                    )
                case .idle:
                    QuickActionCopy(title: "No Orphaned Agents", detail: "Agent processes left behind appear here")
                case .ready(let processes):
                    QuickActionCopy(
                        title: "Stop \(plural(processes.values.count, "Orphaned Agent"))",
                        detail: processes.summary
                    )
                case .performing(let processes):
                    QuickActionCopy(
                        title: "Stopping \(plural(processes.values.count, "Agent"))",
                        detail: "Waiting for the processes to exit"
                    )
                case .failed(let message):
                    QuickActionCopy(title: "Retry Agent Process Scan", detail: message)
                }
            }
        }
        .padding(12)
        .frame(width: 228)
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
