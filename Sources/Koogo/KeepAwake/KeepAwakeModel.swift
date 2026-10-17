import Foundation
import IOKit.pwr_mgt
import Observation
import os

/// app-scoped; started by the app at launch to restore the saved choice. blocking idle display sleep also blocks idle system sleep.
@MainActor
@Observable
final class KeepAwakeModel {
    private static let key = "keep-awake"

    private let defaults: UserDefaults
    @ObservationIgnored private var assertion: IOPMAssertionID?

    /// reads whether the assertion is held; writes save the choice even when macos refuses the assertion.
    var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return assertion != nil
        }
        set {
            defaults.set(newValue, forKey: Self.key)
            hold(newValue)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func start() {
        hold(defaults.bool(forKey: Self.key))
    }

    deinit {
        if let assertion {
            IOPMAssertionRelease(assertion)
        }
    }

    /// notifies on every attempt, since a refused assertion leaves `assertion` unchanged while the toggle shows the request.
    private func hold(_ isHeld: Bool) {
        withMutation(keyPath: \.isEnabled) {
            switch (isHeld, assertion) {
            case (true, nil):
                var id = IOPMAssertionID(0)
                let status = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Koogo keeps the Mac awake" as CFString,
                    &id
                )
                guard status == kIOReturnSuccess else {
                    Logger.app.warning("could not create keep awake assertion: \(status, privacy: .public)")
                    return
                }
                assertion = id
            case (false, let id?):
                IOPMAssertionRelease(id)
                assertion = nil
            case (true, _?), (false, nil):
                break
            }
        }
    }
}
