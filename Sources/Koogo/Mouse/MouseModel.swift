import AppKit
import Observation

/// app-scoped; started once by the app at launch, with observers and tap lasting until process exit.
@MainActor
@Observable
final class MouseModel {
    enum AccessibilityAccess {
        case untrusted
        case granted
        /// trusted, yet the requested tap isn't running; the stale grant usually needs renewing.
        case stale
    }

    private let storage: PersistedValue<MouseSettings>
    private let tap = EventTap()
    private var isTrusted: Bool {
        didSet { applyRules() }
    }

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

    var access: AccessibilityAccess {
        if !isTrusted {
            .untrusted
        } else if tap.isStopped {
            .stale
        } else {
            .granted
        }
    }

    init(defaults: UserDefaults, isInstalled: (String) -> Bool) {
        storage = PersistedValue(key: "mouse-settings", defaults: defaults)
        settings =
            storage.load() ?? MouseSettings(lineByLineApps: MouseSettings.terminalApps.filter(isInstalled))
        isTrusted = AccessibilityPermission.isTrusted
    }

    func start() {
        Task {
            for await isTrusted in AccessibilityPermission.changes {
                self.isTrusted = isTrusted
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
