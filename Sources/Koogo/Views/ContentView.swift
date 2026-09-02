import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(CodexQuotaModel.self) private var codexQuotaModel
    @Environment(BreakReminderModel.self) private var breakReminderModel
    @State private var toolbarHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            PanelToolbar()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    toolbarHeight = height
                }

            PanelPagesView(
                maxHeight: (NSScreen.main?.visibleFrame.height ?? .infinity) - toolbarHeight - 8
            )
        }
        .frame(width: 320)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.94), location: 0),
                    .init(color: .black.opacity(0.94), location: 0.07),
                    .init(color: .black.opacity(0.92), location: 0.14),
                    .init(color: .black.opacity(0.84), location: 0.22),
                    .init(color: .black.opacity(0.68), location: 0.3),
                    .init(color: .black.opacity(0.47), location: 0.37),
                    .init(color: .black.opacity(0.26), location: 0.45),
                    .init(color: .black.opacity(0.1), location: 0.53),
                    .init(color: .black.opacity(0.02), location: 0.61),
                    .init(color: .clear, location: 0.68),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task {
            codexQuotaModel.refresh()
            usageModel.refresh()
            await breakReminderModel.reconcile()
        }
        .breakReminderIssueAlert(breakReminderModel)
    }
}

private struct PanelToolbar: View {
    @Environment(UpdateModel.self) private var updateModel

    private var showsUpdateIndicator: Bool {
        #if DEBUG
        true
        #else
        updateModel.isUpdateAvailable
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            BreakReminderControl()

            Spacer()

            if showsUpdateIndicator {
                Button(action: updateModel.checkForUpdates) {
                    Text("Update")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update available")
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")
        }
        .animation(.smooth(duration: 0.25), value: showsUpdateIndicator)
    }
}
