import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsTab: String {
    case general
    case providers
    case mouse
}

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updateModel
    @Environment(MouseModel.self) private var mouse
    @AppStorage("settings-tab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                SettingsForm {
                    Section("Break Reminder") {
                        BreakReminderIntervalPicker()
                    }

                    Section("System") {
                        LaunchAtLoginToggle()

                        LabeledContent("Check for Updates") {
                            Button("Check Now", action: updateModel.checkForUpdates)
                        }

                        LabeledContent("Accessibility") {
                            if mouse.isTrusted {
                                Text("Granted")
                            } else {
                                Button("Grant", action: AccessibilityPermission.request)
                            }
                        }
                    }
                }
            }

            Tab("Providers", systemImage: "chart.bar.xaxis", value: .providers) {
                SettingsForm {
                    Section("Providers") {
                        ProviderUsageToggles()
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

/// Every tab shares one size so switching tabs never resizes the window; longer tabs scroll.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 500)
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
            isPresented: $failure.isPresent,
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
