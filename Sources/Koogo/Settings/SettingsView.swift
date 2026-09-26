import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updateModel
    @Environment(BreakReminderModel.self) private var breakReminderModel
    @Environment(UsageModel.self) private var usageModel

    var body: some View {
        Form {
            Section("Break Reminder") {
                BreakReminderIntervalPicker()
            }

            Section("Providers") {
                ForEach(UsageProvider.allCases, id: \.self) { provider in
                    Toggle(
                        provider.title,
                        isOn: Binding(
                            get: { usageModel.enabledProviders.contains(provider) },
                            set: { usageModel.setEnabled($0, for: provider) }
                        )
                    )
                }
            }

            Section("System") {
                LaunchAtLoginToggle()

                LabeledContent("Check for Updates") {
                    Button("Check Now", action: updateModel.checkForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 440)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .breakReminderIssueAlert(breakReminderModel)
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
            isPresented: Binding(
                get: { failure != nil },
                set: { isPresented in
                    if !isPresented {
                        failure = nil
                    }
                }
            ),
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
