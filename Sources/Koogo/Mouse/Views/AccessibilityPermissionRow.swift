import SwiftUI

/// a stopped tap with granted trust usually needs the stale grant renewed in system settings.
struct AccessibilityPermissionRow: View {
    private static let accessibilityPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @Environment(MouseModel.self) private var mouse
    @Environment(\.openURL) private var openURL

    var body: some View {
        LabeledContent("Accessibility") {
            switch (mouse.isTrusted, mouse.status) {
            case (false, _):
                Button("Grant", action: AccessibilityPermission.request)
            case (true, .stopped):
                Button("Re-grant") { openURL(Self.accessibilityPane) }
            case (true, _):
                Text("Granted")
            }
        }
    }
}
