import SwiftUI

/// Names a mouse remapping problem and applies its remedy on click. A tap that stays down while trust reads as granted usually means a stale grant, which only System Settings can renew.
struct MouseIssueButton: View {
    private static let accessibilityPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @Environment(MouseModel.self) private var mouse
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch mouse.status {
        case .needsAccessibility:
            badge("Grant Accessibility", action: AccessibilityPermission.request)
        case .stopped:
            badge("Re-grant Accessibility") { openURL(Self.accessibilityPane) }
        case .off, .active:
            EmptyView()
        }
    }

    private func badge(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .capsuleBadge(Color.fallFill)
        }
        .buttonStyle(.plain)
    }
}
