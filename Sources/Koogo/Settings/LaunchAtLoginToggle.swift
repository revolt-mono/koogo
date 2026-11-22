import ServiceManagement
import SwiftUI

struct LaunchAtLoginToggle: View {
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
