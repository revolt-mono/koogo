import SwiftUI

struct MouseSettingsSections: View {
    @Environment(MouseModel.self) private var mouse

    var body: some View {
        @Bindable var mouse = mouse

        Section {
            Toggle("Remap Wheel and Buttons", isOn: $mouse.settings.isEnabled)
        }

        Group {
            Section("Scrolling") {
                Picker("Wheel Step", selection: $mouse.settings.wheelStep) {
                    Text("Slow, 2 Lines").tag(WheelStep.slow)
                    Text("Medium, 3 Lines").tag(WheelStep.medium)
                }

                Picker("Direction", selection: $mouse.settings.direction) {
                    Text("Standard").tag(ScrollDirection.standard)
                    Text("Natural").tag(ScrollDirection.natural)
                }

                Toggle(isOn: $mouse.settings.isOptionPrecisionEnabled) {
                    Text("Option Precision")
                    Text("Hold Option to scroll one line per notch.")
                }
            }

            Section("Line-by-Line Apps") {
                LineByLineAppList()
            }

            Section("Buttons") {
                Toggle(isOn: $mouse.settings.isLookUpEnabled) {
                    Text("Look Up")
                    Text("Mouse button 4 looks up the word under the pointer.")
                }
            }
        }
        .disabled(!mouse.settings.isEnabled)
    }
}
