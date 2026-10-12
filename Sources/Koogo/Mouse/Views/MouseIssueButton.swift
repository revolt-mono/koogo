import SwiftUI

/// Flags a mouse remapping problem and opens the settings tab that resolves it.
struct MouseIssueButton: View {
    @Environment(MouseModel.self) private var mouse
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var body: some View {
        if let issue = mouse.status.issue {
            Button {
                settingsTab = .general
                openSettings()
            } label: {
                Text("\(Image(systemName: "exclamationmark"))")
                    .capsuleBadge(Color.fallFill)
            }
            .buttonStyle(.plain)
            .help(issue)
            .accessibilityLabel(issue)
        }
    }
}

extension MouseStatus {
    fileprivate var issue: LocalizedStringKey? {
        switch self {
        case .needsAccessibility: "Mouse remapping needs Accessibility. Check it in General settings."
        case .stopped: "macOS stopped passing mouse events. Check Accessibility in General settings."
        case .off, .active: nil
        }
    }
}
