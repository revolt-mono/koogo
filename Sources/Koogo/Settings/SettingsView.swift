import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String {
    case general
    case providers
    case mouse

    static let storageKey = "settings-tab"
}

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updateModel
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                SettingsForm {
                    Section("Break Reminder") {
                        BreakReminderIntervalPicker()
                    }

                    Section("System") {
                        LaunchAtLoginToggle()

                        AccessibilityCheck()

                        LabeledContent("Check for Updates") {
                            Button("Check Now", action: updateModel.checkForUpdates)
                        }
                    }
                }
            }

            Tab("Providers", systemImage: "chart.bar.xaxis", value: .providers) {
                SettingsForm {
                    Section("Providers") {
                        ProviderUsageToggles()
                    }

                    Section("Fetch Quota") {
                        ProviderQuotaToggles()
                    }
                }
            }

            Tab("Mouse", systemImage: "computermouse", value: .mouse) {
                SettingsForm {
                    MouseSettingsSections()
                }
            }
        }
        .background { SettingsWindowStyle() }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Every tab shares one size, a little taller than Providers, so switching tabs never resizes the window; longer tabs scroll.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 462)
    }
}

/// Drops the full-size content view style from the hosting window. With that style, a switch's glass press interaction on macOS 26 leaves the title bar unable to start a window drag.
private struct SettingsWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowStyleView {
        WindowStyleView()
    }

    func updateNSView(_: WindowStyleView, context: Context) {}

    final class WindowStyleView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.styleMask.remove(.fullSizeContentView)
        }
    }
}

/// Checks Accessibility on demand. A grant briefly replaces the button with a confirmation; a missing grant is left to the system prompt.
private struct AccessibilityCheck: View {
    private enum Phase {
        case ready
        case confirmedGranted
    }

    @Environment(MouseModel.self) private var mouse
    @State private var phase = Phase.ready

    var body: some View {
        LabeledContent("Accessibility") {
            Group {
                if phase == .ready {
                    Button("Check Now") {
                        mouse.checkAccessibility()
                        if mouse.isTrusted {
                            phase = .confirmedGranted
                        }
                    }
                } else {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .transition(.blurReplace)
        }
        .motionAnimation(.smooth(duration: 0.35), value: phase)
        .task(id: phase) {
            guard phase == .confirmedGranted, (try? await Task.sleep(for: .seconds(2))) != nil else {
                return
            }
            phase = .ready
        }
    }
}

private struct LaunchAtLoginToggle: View {
    private static var isRegistered: Bool { SMAppService.mainApp.status == .enabled }

    @State private var launchesAtLogin = Self.isRegistered
    @State private var failure: (any Error)?

    var body: some View {
        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { launchesAtLogin },
                set: setLaunchesAtLogin
            )
        )
        .onAppear {
            launchesAtLogin = Self.isRegistered
        }
        .alert(
            "Couldn't Change Login Setting",
            isPresented: $failure.isPresent(),
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func setLaunchesAtLogin(_ launches: Bool) {
        do {
            if launches {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }

        launchesAtLogin = Self.isRegistered
    }
}
