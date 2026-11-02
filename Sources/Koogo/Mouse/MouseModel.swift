import AppKit
import Observation

/// app-scoped; started once by the app at launch, with observers and tap lasting until process exit.
@MainActor
@Observable
final class MouseModel {
    private let storage: PersistedValue<MouseSettings>
    private let tap = EventTap()
    private(set) var isTrusted = false

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

    /// an enabled, trusted tap that is not running usually needs its stale grant renewed.
    var isTapStopped: Bool {
        settings.isEnabled && isTrusted && !tap.isRunning
    }

    init(defaults: UserDefaults, isInstalled: (String) -> Bool) {
        storage = PersistedValue(key: "mouse-settings", defaults: defaults)
        settings =
            storage.load() ?? MouseSettings(lineByLineApps: MouseSettings.terminalApps.filter(isInstalled))
    }

    func start() {
        Task {
            for await _ in AccessibilityPermission.changes {
                // accessibility notifications arrive before the trust query reflects the change.
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
                applyRules()
            }
        }
        isTrusted = AccessibilityPermission.isTrusted
        applyRules()
    }

    private func applyRules() {
        if settings.isEnabled, isTrusted {
            tap.run(InputRules(settings, frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
        } else {
            tap.pause()
        }
    }
}
