import AppKit
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
          GeneralSettingsSections()
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

  @AppStorage("settings-tab") private var tab = SettingsTab.general
}

private struct GeneralSettingsSections: View {
  var body: some View {
    Section("Break Reminder") {
      BreakReminderIntervalPicker()
    }

    Section("Utility") {
      KeepAwakeToggle()

      AccessibilityPermissionRow()
    }

    Section("System") {
      LaunchAtLoginToggle()

      CheckForUpdatesRow()
    }
  }
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
