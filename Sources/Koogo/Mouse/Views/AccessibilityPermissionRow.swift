import SwiftUI

/// A tap that stays down while trust reads as granted usually means a stale grant, which only System Settings can renew.
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
