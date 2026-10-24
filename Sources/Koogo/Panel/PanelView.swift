import AppKit
import SwiftUI

struct PanelView: View {
    private static let toolbarGap: CGFloat = 8

    @Environment(ProviderPreferences.self) private var preferences
    @Environment(UsageModel.self) private var usageModel
    @Environment(QuotaModel.self) private var quotaModel
    @State private var toolbarHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: Self.toolbarGap) {
            PanelToolbar()
                .padding(.horizontal, PanelLayout.inset)
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    toolbarHeight = height
                }

            PanelPager(maxHeight: (NSScreen.main?.visibleFrame.height ?? .infinity) - toolbarHeight - Self.toolbarGap)
        }
        .frame(width: 320)
        .foregroundStyle(.panelLabel)
        .background {
            let backdrop = Color(red: 0x13 / 255, green: 0x12 / 255, blue: 0x11 / 255)
            LinearGradient(
                stops: [
                    .init(color: backdrop.opacity(0.72), location: 0),
                    .init(color: backdrop.opacity(0.6), location: 0.21),
                    .init(color: backdrop.opacity(0.38), location: 0.42),
                    .init(color: backdrop.opacity(0.14), location: 0.59),
                    .init(color: backdrop.opacity(0), location: 0.7),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task(id: preferences.usageProviders) {
            usageModel.refresh(providers: preferences.usageProviders)
        }
        .task(id: preferences.quotaProviders) {
            quotaModel.refresh(preferences.quotaProviders)
        }
    }
}

private struct PanelToolbar: View {
    @Environment(UpdateModel.self) private var updateModel

    var body: some View {
        HStack(spacing: 8) {
            BreakReminderControl()

            Spacer()

            if updateModel.isUpdateAvailable {
                UpdateAvailableButton()
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Settings")
        }
        .motionAnimation(.smooth(duration: 0.25), value: updateModel.isUpdateAvailable)
    }
}
