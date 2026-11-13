import AppKit
import SwiftUI

struct QuickActionsPopoverContent: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Quick Actions")
        .fontWeight(.semibold)

      VStack(spacing: 8) {
        QuickActionRow(model: systemAppearance, systemImage: "circle.lefthalf.filled") { phase in
          switch phase {
          case .unscanned,
               .scanning,
               .idle,
               .ready:
            QuickActionCopy(title: "Toggle System Appearance", detail: "Switch macOS light and dark mode")
          case .performing:
            QuickActionCopy(title: "Changing System Appearance", detail: "Waiting for System Events")
          case .scanFailed(let message),
               .performFailed(let message):
            QuickActionCopy(title: "System Appearance Failed", detail: message)
          }
        }

        QuickActionRow(model: diskImages, systemImage: "eject") { phase in
          switch phase {
          case .unscanned,
               .scanning:
            QuickActionCopy(title: "Checking Disk Images", detail: "Looking for visible mounted DMGs")

          case .idle:
            QuickActionCopy(title: "No Mounted DMGs", detail: "Visible disk images appear here")

          case .ready(let diskImages):
            QuickActionCopy(
              title: "Eject \(plural(diskImages.values.count, "Mounted DMG"))",
              detail: diskImages.values.map(\.name).joined(separator: ", "),
            )

          case .performing(let diskImages):
            QuickActionCopy(
              title: "Ejecting \(plural(diskImages.values.count, "DMG"))",
              detail: "Waiting for macOS",
            )

          case .scanFailed(let message):
            QuickActionCopy(title: "Retry Disk Image Scan", detail: message)

          case .performFailed(let message):
            QuickActionCopy(title: "Eject Failed", detail: message)
          }
        }
        .onReceive(Self.volumes.publisher(for: NSWorkspace.didMountNotification)) { _ in
          diskImages.refresh()
        }
        .onReceive(Self.volumes.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
          diskImages.refresh()
        }

        QuickActionRow(model: agentProcesses, systemImage: "xmark.octagon") { phase in
          switch phase {
          case .unscanned,
               .scanning:
            QuickActionCopy(
              title: "Checking Agent Processes",
              detail: "Looking for orphaned \(Self.agentNames)",
            )

          case .idle:
            QuickActionCopy(title: "No Orphaned Agents", detail: "Agent processes left behind appear here")

          case .ready(let processes):
            QuickActionCopy(
              title: "Stop \(plural(processes.values.count, "Orphaned Agent"))",
              detail: processes.summary,
            )

          case .performing(let processes):
            QuickActionCopy(
              title: "Stopping \(plural(processes.values.count, "Agent"))",
              detail: "Waiting for the processes to exit",
            )

          case .scanFailed(let message):
            QuickActionCopy(title: "Retry Agent Process Scan", detail: message)

          case .performFailed(let message):
            QuickActionCopy(title: "Stop Failed", detail: message)
          }
        }

        QuickActionRow(model: lingeringApps, systemImage: "xmark.app") { phase in
          switch phase {
          case .unscanned,
               .scanning:
            QuickActionCopy(
              title: "Checking Lingering Apps",
              detail: "Looking for quit apps running in the background",
            )

          case .idle:
            QuickActionCopy(
              title: "No Lingering Apps",
              detail: "Quit apps still running in the background appear here",
            )

          case .ready(let apps):
            QuickActionCopy(
              title: "Stop \(plural(apps.values.count, "Lingering App"))",
              detail: apps.summary,
            )

          case .performing(let apps):
            QuickActionCopy(
              title: "Stopping \(plural(apps.values.count, "App"))",
              detail: "Waiting for the processes to exit",
            )

          case .scanFailed(let message):
            QuickActionCopy(title: "Retry Lingering App Scan", detail: message)

          case .performFailed(let message):
            QuickActionCopy(title: "Stop Failed", detail: message)
          }
        }
      }
    }
  }

  private static let volumes = NSWorkspace.shared.notificationCenter
  private static let agentNames = OrphanedAgentProcess.providers.map { $0.title.lowercased() }
    .formatted(.list(type: .and).locale(.display))

  @State private var systemAppearance = QuickActionModel(perform: SystemAppearance.toggle)
  @State private var diskImages = QuickActionModel(scan: MountedDiskImages.mounted) { try await $0.eject() }
  @State private var agentProcesses = QuickActionModel(scan: OrphanedAgentProcesses.running) {
    try $0.forceTerminate()
  }

  @State private var lingeringApps = QuickActionModel(scan: LingeringApps.running) { try await $0.forceTerminate() }

  private func plural(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }
}
