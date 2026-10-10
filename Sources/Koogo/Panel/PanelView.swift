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

            PanelPagesView(
                maxHeight: (NSScreen.main?.visibleFrame.height ?? .infinity) - toolbarHeight - Self.toolbarGap
            )
        }
        .frame(width: 320)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.94), location: 0.15),
                    .init(color: .black.opacity(0.94), location: 0.22),
                    .init(color: .black.opacity(0.92), location: 0.28),
                    .init(color: .black.opacity(0.84), location: 0.35),
                    .init(color: .black.opacity(0.68), location: 0.42),
                    .init(color: .black.opacity(0.47), location: 0.48),
                    .init(color: .black.opacity(0.26), location: 0.55),
                    .init(color: .black.opacity(0.1), location: 0.62),
                    .init(color: .black.opacity(0.02), location: 0.68),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .onAppear {
            usageModel.refresh(providers: preferences.usageProviders)
            quotaModel.refresh(preferences.quotaProviders)
        }
        .onChange(of: preferences.usageProviders) { _, providers in
            usageModel.refresh(providers: providers)
        }
        .onChange(of: preferences.quotaProviders) { _, providers in
            quotaModel.refresh(providers)
        }
    }
}

private struct PanelToolbar: View {
    @Environment(UpdateModel.self) private var updateModel

    var body: some View {
        HStack(spacing: 8) {
            BreakReminderControl()

            Spacer()

            if updateModel.showsUpdateIndicator {
                UpdateAvailableButton()
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
        .motionAnimation(.smooth(duration: 0.25), value: updateModel.showsUpdateIndicator)
    }
}
