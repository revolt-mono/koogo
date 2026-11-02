import SwiftUI

struct AccessibilityPermissionRow: View {
    private static let accessibilityPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @Environment(MouseModel.self) private var mouse
    @Environment(\.openURL) private var openURL

    var body: some View {
        LabeledContent {
            if !mouse.isTrusted {
                Button("Grant", action: AccessibilityPermission.request)
            } else if mouse.isTapStopped {
                Button("Re-grant") { openURL(Self.accessibilityPane) }
            } else {
                Text("Granted")
            }
        } label: {
            Text("Accessibility")
            Text("Lets Koogo remap the mouse wheel and buttons.")
        }
    }
}
