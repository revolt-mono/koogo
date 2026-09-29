import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updateModel

    var body: some View {
        Form {
            Section("Break Reminder") {
                BreakReminderIntervalPicker()
            }

            Section("Providers") {
                UsageProviderToggles()
            }

            Section("Fetch Quota") {
                QuotaProviderToggles()
            }

            Section("System") {
                LaunchAtLoginToggle()

                LabeledContent("Check for Updates") {
                    Button("Check Now", action: updateModel.checkForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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

/// Drops the full-size content view style from the hosting window. With that style, a switch's glass
/// press interaction on macOS 26 leaves the title bar unable to start a window drag.
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
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var failure: (any Error)?

    var body: some View {
        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { isEnabled },
                set: setEnabled
            )
        )
        .onAppear {
            isEnabled = SMAppService.mainApp.status == .enabled
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

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }

        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
