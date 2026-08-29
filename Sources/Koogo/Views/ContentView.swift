import SwiftUI

struct ContentView: View {
    @Environment(UsageModel.self) private var usageModel
    @Environment(CodexQuotaModel.self) private var codexQuotaModel

    var body: some View {
        VStack(spacing: 8) {
            PanelToolbar()
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Group {
                if let snapshot = usageModel.snapshot {
                    UsagePanelView(snapshot: snapshot)
                        .transition(.blurReplace)
                } else {
                    UsageLoadingView()
                        .transition(.blurReplace)
                }
            }
        }
        .frame(width: 300)
        .background {
            let tint = Color(
                .sRGB,
                red: 12.0 / 255,
                green: 21.0 / 255,
                blue: 22.0 / 255,
                opacity: 1
            )

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.94), location: 0),
                    .init(color: .black.opacity(0.92), location: 0.07),
                    .init(color: tint.opacity(0.7), location: 0.22),
                    .init(color: tint.opacity(0.4), location: 0.36),
                    .init(color: tint.opacity(0.16), location: 0.48),
                    .init(color: .clear, location: 0.6),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.smooth(duration: 0.35), value: usageModel.snapshot != nil)
        .task {
            codexQuotaModel.refresh()
            usageModel.refresh()
        }
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
