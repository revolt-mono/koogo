import AppKit
import Combine
import SwiftUI

struct QuickActionsPopoverContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 2)

            SystemAppearanceQuickAction()
            MountedDiskImagesQuickAction()
        }
        .padding(12)
        .frame(width: 228)
    }
}

private struct SystemAppearanceQuickAction: View {
    private enum State {
        case ready
        case changing
        case failed(String)
    }

    @State private var state = State.ready

    var body: some View {
        switch state {
        case .ready:
            QuickActionRow(
                title: "Toggle System Appearance",
                detail: "Switch macOS light and dark mode",
                interaction: .action(
                    systemImage: "circle.lefthalf.filled",
                    perform: toggle
                )
            )
        case .changing:
            QuickActionRow(
                title: "Changing System Appearance",
                detail: "Waiting for System Events",
                interaction: .working
            )
        case .failed(let message):
            QuickActionRow(
                title: "Retry System Appearance",
                detail: message,
                interaction: .action(
                    systemImage: "exclamationmark.triangle",
                    perform: toggle
                )
            )
        }
    }

    private func toggle() {
        state = .changing
        Task {
            do {
                try await SystemQuickActions.toggleSystemAppearance()
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct MountedDiskImagesQuickAction: View {
    private enum State {
        case loading
        case none
        case available(MountedDiskImages)
        case ejecting(MountedDiskImages)
        case failed(String)
    }

    @State private var state = State.loading
    @State private var reloadRequest = 0

    var body: some View {
        Group {
            switch state {
            case .loading:
                QuickActionRow(
                    title: "Checking Disk Images",
                    detail: "Looking for visible mounted DMGs",
                    interaction: .working
                )
            case .none:
                QuickActionRow(
                    title: "No Mounted DMGs",
                    detail: "Visible disk images appear here",
                    interaction: .unavailable(systemImage: "eject")
                )
            case .available(let diskImages):
                let count = diskImages.values.count
                QuickActionRow(
                    title: "Eject \(count) Mounted DMG\(count == 1 ? "" : "s")",
                    detail: diskImages.values.map(\.name).joined(separator: ", "),
                    interaction: .action(systemImage: "eject") {
                        eject(diskImages)
                    }
                )
            case .ejecting(let diskImages):
                let count = diskImages.values.count
                QuickActionRow(
                    title: "Ejecting \(count) DMG\(count == 1 ? "" : "s")",
                    detail: "Waiting for macOS",
                    interaction: .working
                )
            case .failed(let message):
                QuickActionRow(
                    title: "Retry Disk Image Scan",
                    detail: message,
                    interaction: .action(systemImage: "exclamationmark.triangle") {
                        reloadRequest &+= 1
                    }
                )
            }
        }
        .task(id: reloadRequest, load)
        .onReceive(
            Publishers.Merge(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didMountNotification
                ),
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didUnmountNotification
                )
            )
        ) { _ in
            reloadRequest &+= 1
        }
    }

    private func load() async {
        if case .ejecting = state {
            return
        }

        state = .loading
        do {
            let diskImages = try await SystemQuickActions.mountedDiskImages()
            guard !Task.isCancelled else {
                return
            }
            state = diskImages.map(State.available) ?? .none
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func eject(_ diskImages: MountedDiskImages) {
        state = .ejecting(diskImages)
        Task {
            do {
                try await SystemQuickActions.eject(diskImages)
                state = try await SystemQuickActions.mountedDiskImages().map(State.available) ?? .none
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct QuickActionRow: View {
    enum Interaction {
        case action(systemImage: String, perform: @MainActor () -> Void)
        case working
        case unavailable(systemImage: String)

        var isEnabled: Bool {
            if case .action = self {
                true
            } else {
                false
            }
        }
    }

    let title: String
    let detail: String
    let interaction: Interaction
    @State private var isHovered = false

    var body: some View {
        Button {
            if case .action(_, let perform) = interaction {
                perform()
            }
        } label: {
            HStack(spacing: 8) {
                Group {
                    switch interaction {
                    case .working:
                        ProgressView()
                            .controlSize(.small)
                    case .action(let systemImage, _), .unavailable(let systemImage):
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
                .background(
                    Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background(
                Color.white.opacity(isHovered && interaction.isEnabled ? 0.1 : 0.06),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!interaction.isEnabled)
        .opacity(interaction.isEnabled ? 1 : 0.58)
        .onHover { isHovered = $0 }
    }
}
