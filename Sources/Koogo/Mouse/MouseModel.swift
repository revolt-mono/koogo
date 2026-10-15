import AppKit
import Observation

enum MouseStatus {
    case off
    case needsAccessibility
    case active
    case stopped
}

/// app-scoped; started once by the app at launch, with observers and tap lasting until process exit.
@MainActor
@Observable
final class MouseModel {
    private let storage: PersistedValue<MouseSettings>
    private let tap = EventTap()
    private(set) var isTrusted = false
    @ObservationIgnored private var frontmostApp: String?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

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
        switch (settings.isEnabled, isTrusted, tap.isRunning) {
        case (false, _, _): .off
        case (true, false, _): .needsAccessibility
        case (true, true, true): .active
        case (true, true, false): .stopped
        }
    }

    /// defers accessibility and tap access until start; unsaved settings use installed terminals as line-by-line apps.
    init(defaults: UserDefaults, isInstalled: (String) -> Bool) {
        storage = PersistedValue(key: "mouse-settings", defaults: defaults)
        settings =
            storage.load() ?? MouseSettings(lineByLineApps: MouseSettings.terminalApps.filter(isInstalled))
    }

    func start() {
        guard observers.isEmpty else {
            return
        }
        observers = [
            Task {
                for await _ in AccessibilityPermission.changes {
                    // accessibility notifications arrive before the trust query reflects the change.
                    try? await Task.sleep(for: .milliseconds(250))
                    isTrusted = AccessibilityPermission.isTrusted
                    applyRules()
                }
            },
            Task {
                let activations = NSWorkspace.shared.notificationCenter.notifications(
                    named: NSWorkspace.didActivateApplicationNotification
                )
                for await _ in activations {
                    frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    applyRules()
                }
            },
        ]
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
