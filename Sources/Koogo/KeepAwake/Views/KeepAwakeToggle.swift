import SwiftUI

struct KeepAwakeToggle: View {
  var body: some View {
    @Bindable var keepAwake = keepAwake

    Toggle(isOn: $keepAwake.isEnabled) {
      Text("Keep Awake")
      Text("Keeps the display and Mac from sleeping while idle.")
    }
  }

  @Environment(KeepAwakeModel.self) private var keepAwake
}
