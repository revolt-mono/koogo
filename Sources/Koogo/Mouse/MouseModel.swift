import AppKit
import Observation

enum MouseStatus: Equatable {
    case off
    case needsAccessibility
    case active
    case stopped

    init(isEnabled: Bool, isTrusted: Bool, isTapRunning: Bool) {
        self =
            switch (isEnabled, isTrusted, isTapRunning) {
            case (false, _, _): .off
            case (true, false, _): .needsAccessibility
            case (true, true, true): .active
            case (true, true, false): .stopped
            }
    }
}

@MainActor
@Observable
final class MouseModel {
    private let storage: PersistedValue<MouseSettings>
    private let tap = EventTap()
    private(set) var isTrusted = false
    @ObservationIgnored private var frontmostApp: String?

    var settings: MouseSettings {
        didSet {
            guard settings != oldValue else {
                return
            }
            storage.save(settings)
            applyRules()
            if settings.isEnabled, !oldValue.isEnabled, !isTrusted {
                AccessibilityPermission.request()
            }
        }
    }

    var status: MouseStatus {
        MouseStatus(isEnabled: settings.isEnabled, isTrusted: isTrusted, isTapRunning: tap.isRunning)
    }

    /// Touches neither Accessibility nor the tap until `start()`. Until the user saves settings, the installed terminals stand in as line-by-line apps.
    init(
        defaults: UserDefaults = .standard,
        isInstalled: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) {
        storage = PersistedValue(key: "mouse-settings", defaults: defaults)
        settings =
            storage.load() ?? MouseSettings(lineByLineApps: MouseSettings.terminalApps.filter(isInstalled))
    }

    /// Reads Accessibility trust and the frontmost app, then follows each for the rest of the process. Call once, at launch.
    func start() {
        Task {
            for await _ in AccessibilityPermission.changes {
                // The notification arrives before AXIsProcessTrusted reflects the change.
                try? await Task.sleep(for: .milliseconds(250))
                isTrusted = AccessibilityPermission.isTrusted
                applyRules()
            }
        }
        Task {
            let activations = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            )
            for await _ in activations {
                frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                applyRules()
            }
        }
        isTrusted = AccessibilityPermission.isTrusted
        frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        applyRules()
    }

    private func applyRules() {
        if settings.isEnabled, isTrusted {
            tap.run(InputRules(settings, frontmostApp: frontmostApp))
        } else {
            tap.pause()
        }
    }
}
