import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsTab: String {
  case general
  case providers
  case mouse
}

struct SettingsView: View {
  var body: some View {
    TabView(selection: $tab) {
      Tab("General", systemImage: "gearshape", value: .general) {
        SettingsForm {
          Section("Break Reminder") {
            BreakReminderIntervalPicker()
          }

          Section("Utility") {
            @Bindable var keepAwake = keepAwake
            Toggle(isOn: $keepAwake.isEnabled) {
              Text("Keep Awake")
              Text("Keeps the display and Mac from sleeping while idle.")
            }

            AccessibilityPermissionRow()
          }

          Section("System") {
            LaunchAtLoginToggle()

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

  @Environment(UpdateModel.self) private var updateModel
  @Environment(KeepAwakeModel.self) private var keepAwake
  @AppStorage("settings-tab") private var tab = SettingsTab.general
}

private struct SettingsForm<Content: View>: View {
  @ContentBuilder let content: Content

  var body: some View {
    Form {
      content
    }
    .formStyle(.grouped)
    .frame(width: 440, height: 500)
    .navigationTitle("Settings")
  }
}

/// macos 26 breaks title-bar dragging in full-size content windows after a glass switch press.
private struct SettingsWindowStyle: NSViewRepresentable {
  final class WindowStyleView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.styleMask.remove(.fullSizeContentView)
    }
  }

  func makeNSView(context _: Context) -> WindowStyleView {
    WindowStyleView()
  }

  func updateNSView(_: WindowStyleView, context _: Context) { }
}

private struct LaunchAtLoginToggle: View {
  var body: some View {
    Toggle(
      isOn: Binding(
        get: { status == .enabled || status == .requiresApproval },
        set: setLaunchesAtLogin,
      )
    ) {
      Text("Launch at Login")
      if status == .requiresApproval {
        Text("Allow Koogo in Login Items to finish.")
      }
    }
    .onAppear {
      status = SMAppService.mainApp.status
    }
    .alert(
      "Couldn't Change Login Setting",
      isPresented: Binding {
        failure != nil
      } set: {
        if !$0 {
          failure = nil
        }
      },
      presenting: failure,
    ) { _ in
    } message: { error in
      Text(error.localizedDescription)
    }
  }

  @State private var status = SMAppService.mainApp.status
  @State private var failure: any Error?

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
    status = SMAppService.mainApp.status
    if status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }
}
