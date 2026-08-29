import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(UpdateModel.self) private var updateModel
    @State private var isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: (any Error)?

    private var isPresentingLaunchAtLoginError: Binding<Bool> {
        Binding(
            get: { launchAtLoginError != nil },
            set: { isPresented in
                if !isPresented {
                    launchAtLoginError = nil
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { isLaunchAtLoginEnabled },
                        set: setLaunchAtLogin
                    )
                )
            }

            Section("Software Updates") {
                LabeledContent("Check for Updates") {
                    Button("Check Now", action: updateModel.checkForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 208)
        .onAppear {
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .alert(
            "Couldn't Change Login Setting",
            isPresented: isPresentingLaunchAtLoginError,
            presenting: launchAtLoginError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error
        }

        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}
